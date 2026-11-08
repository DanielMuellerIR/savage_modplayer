#include "VideoRenderer.h"
#include <QFile>
#include <QFontDatabase>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThread>
#include <QElapsedTimer>
#include <QtEndian>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <csignal>
#include <cstdio>
#include <stdexcept>

namespace {
volatile std::sig_atomic_t cancelled = 0;
void interrupted(int) { cancelled = 1; }
bool black(int key) { return key % 12 == 1 || key % 12 == 3 || key % 12 == 6 || key % 12 == 8 || key % 12 == 10; }
QColor channelColor(int channel) { return QColor::fromHsvF(std::fmod(channel * 0.381966 + 0.54, 1.0), 0.58, 0.88); }
QString noteName(int key) { static const QStringList names = {"C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"}; return names[key % 12] + QString::number(key / 12); }
QJsonDocument readJSON(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > 32 * 1024 * 1024) throw std::runtime_error("Ungültige Videodaten");
    QJsonParseError error;
    auto json = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError) throw std::runtime_error("Ungültige Video-JSON-Daten");
    return json;
}
quint32 word(const QByteArray &bytes, qsizetype offset) {
    if (offset < 0 || offset + 4 > bytes.size()) throw std::runtime_error("Beschädigtes MOV-Atom");
    return qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(bytes.constData() + offset));
}
void setWord(QByteArray &bytes, qsizetype offset, quint32 value) {
    if (offset < 0 || offset + 4 > bytes.size()) throw std::runtime_error("Beschädigtes MOV-Feld");
    qToBigEndian<quint32>(value, reinterpret_cast<uchar *>(bytes.data() + offset));
}
QByteArray atom(const QByteArray &type, const QByteArray &payload) {
    QByteArray result(8, '\0'); setWord(result, 0, quint32(payload.size() + 8)); result.replace(4, 4, type); return result + payload;
}
QList<QByteArray> children(const QByteArray &payload) {
    QList<QByteArray> result;
    for (qsizetype i = 0; i < payload.size();) {
        auto size = word(payload, i);
        if (size < 8 || size > payload.size() - i) throw std::runtime_error("Unzulässige MOV-Atomgröße");
        result << payload.mid(i, size); i += size;
    }
    return result;
}
bool videoTrack(const QByteArray &track) {
    for (const auto &mdia : children(track.mid(8))) if (mdia.mid(4, 4) == "mdia")
        for (const auto &child : children(mdia.mid(8))) if (child.mid(4, 4) == "hdlr" && child.mid(16, 4) == "vide") return true;
    return false;
}
QByteArray trimAtom(const QByteArray &value, quint32 frames, quint32 audioFrames, quint32 step, bool video = false) {
    const auto type = value.mid(4, 4);
    if (type == "trak") video = videoTrack(value);
    if (type == "stts" && video) {
        quint64 samples = 0;
        const auto count = word(value, 12);
        for (quint32 i = 0; i < count; ++i) {
            samples += word(value, 16 + 8 * i);
            if (word(value, 20 + 8 * i) != step) throw std::runtime_error("Unerwartete Video-Zeitbasis");
        }
        if (samples != frames || audioFrames <= quint64(frames - 1) * step) throw std::runtime_error("Video-Zeitbasis stimmt nicht mit Audio überein");
        QByteArray payload(8 + (frames > 1 ? 16 : 8), '\0'); setWord(payload, 4, frames > 1 ? 2 : 1);
        qsizetype offset = 8;
        if (frames > 1) { setWord(payload, offset, frames - 1); setWord(payload, offset + 4, step); offset += 8; }
        setWord(payload, offset, 1); setWord(payload, offset + 4, audioFrames - (frames - 1) * step);
        return atom(type, payload);
    }
    if (type == "mvhd" || (video && (type == "mdhd" || type == "tkhd"))) {
        auto result = value;
        if (quint8(value[8]) != 0) throw std::runtime_error("Unerwartetes MOV-Zeitformat");
        if (type != "tkhd" && word(value, 20) != 48000) throw std::runtime_error("MOV hat keine Sample-Zeitbasis");
        setWord(result, type == "tkhd" ? 28 : 24, audioFrames); return result;
    }
    if (type == "elst" && video) {
        if (quint8(value[8]) != 0 || word(value, 12) != 1) throw std::runtime_error("Unerwartete MOV-Schnittliste");
        auto result = value; setWord(result, 16, audioFrames); return result;
    }
    if (type == "moov" || type == "trak" || type == "mdia" || type == "minf" || type == "stbl" || type == "edts") {
        QByteArray payload;
        for (auto child : children(value.mid(8))) payload += trimAtom(child, frames, audioFrames, step, video);
        return atom(type, payload);
    }
    return value;
}
void trimLastFrame(const QString &path, quint32 frameCount, quint32 audioFrames, quint32 step) {
    // MOV liegt hinter mdat: Die letzte Bilddauer darf kürzer sein, ohne
    // Audio umzuschreiben oder die vorhandenen Chunk-Offsets zu verschieben.
    QFile file(path);
    if (!file.open(QIODevice::ReadWrite)) throw std::runtime_error("Video lässt sich nicht abschließen");
    for (qint64 position = 0; position < file.size();) {
        if (!file.seek(position)) throw std::runtime_error("MOV-Position nicht lesbar");
        auto header = file.read(16);
        if (header.size() < 8) throw std::runtime_error("MOV-Header fehlt");
        quint64 size = word(header, 0);
        if (size == 1) size = qFromBigEndian<quint64>(reinterpret_cast<const uchar *>(header.constData() + 8));
        if (size < 8 || size > quint64(file.size() - position)) throw std::runtime_error("Ungültige MOV-Länge");
        if (header.mid(4, 4) == "moov") {
            if (position + qint64(size) != file.size() || size > 32 * 1024 * 1024) throw std::runtime_error("MOV-Metadaten liegen nicht am Dateiende");
            file.seek(position); auto bytes = file.read(size);
            auto result = trimAtom(bytes, frameCount, audioFrames, step);
            file.seek(position);
            if (file.write(result) != result.size() || !file.resize(position + result.size()) || !file.flush()) throw std::runtime_error("MOV-Abschluss fehlgeschlagen");
            return;
        }
        position += qint64(size);
    }
    throw std::runtime_error("MOV-Metadaten fehlen");
}
void draw(QImage &image, const QJsonObject &manifest, const QJsonArray &source, quint64 sampleFrame) {
    const auto options = manifest["options"].toObject(), audio = options["audio"].toObject();
    const bool light = options["appearance"].toString() == "light";
    const int width = image.width(), height = image.height(), lookahead = options["lookaheadSeconds"].toInt(4);
    int low = 0, high = 119;
    if (options["keyRange"].isArray()) { auto range = options["keyRange"].toArray(); low = range[0].toInt(); high = range[1].toInt(); }
    else { auto range = options["keyRange"].toObject(); low = range["lowerBound"].toInt(0); high = range["upperBound"].toInt(119); }
    if (black(low)) --low; if (black(high)) ++high;
    low = std::clamp(low, 0, 119); high = std::clamp(high, low, 119);
    QList<int> keys, whites;
    for (int key = low; key <= high; ++key) { keys << key; if (!black(key)) whites << key; }
    const double keyWidth = std::max(1., std::min((width - 60.) / whites.size(), std::min(144., (height - 76.) * 0.28) / 4.8));
    const double keyboardHeight = keyWidth * 4.8, left = 42 + (width - 60 - keyWidth * whites.size()) / 2,
        right = width - left - keyWidth * whites.size(), strike = height - 22 - keyboardHeight, scale = std::max(1., strike - 64) / lookahead;
    double centers[120] = {}; int whiteIndex = 0;
    for (auto key : keys) { centers[key] = left + whiteIndex * keyWidth + (black(key) ? 0 : keyWidth / 2); if (!black(key)) ++whiteIndex; }
    QList<int> mutes, solos;
    for (auto value : audio["mutedChannels"].toArray()) mutes << value.toInt();
    for (auto value : audio["soloChannels"].toArray()) solos << value.toInt();
    auto visible = [&](int channel) { return channel >= 0 && channel < 64 && !mutes.contains(channel) && (solos.isEmpty() || solos.contains(channel)); };
    const auto foreground = QColor(light ? "#13171d" : "#eceef0");
    QPainter p(&image); p.setRenderHint(QPainter::Antialiasing);
    p.fillRect(image.rect(), QColor(light ? "#f6f7fa" : "#050608"));
    auto text = [&](const QString &value, QPointF point, int size, QColor color, double maximum = 100000) {
        auto font = QFontDatabase::systemFont(QFontDatabase::FixedFont); font.setPixelSize(size); p.setFont(font); p.setPen(color);
        p.drawText(point, p.fontMetrics().elidedText(value, Qt::ElideMiddle, qRound(maximum)));
    };
    text(manifest["title"].toString().isEmpty() ? manifest["format"].toString() : manifest["title"].toString(), {20,26}, 16, foreground, width - 186);
    auto milliseconds = sampleFrame * 1000 / 48000;
    text(QString("%1:%2.%3").arg(milliseconds / 60000, 2, 10, QChar('0')).arg(milliseconds / 1000 % 60, 2, 10, QChar('0')).arg(milliseconds % 1000, 3, 10, QChar('0')), {double(width - 150),26}, 13, foreground);
    text(manifest["format"].toString() + " · " + QString::number(manifest["channelCount"].toInt()) + " ch", {20,45}, 10, foreground);
    const auto faint = QColor(light ? 0 : 255, light ? 0 : 255, light ? 0 : 255, 20);
    for (auto key : keys) {
        if (black(key)) p.fillRect(QRectF(centers[key] - keyWidth * .31, 64, keyWidth * .62, strike - 64), QColor(light ? 0 : 255, light ? 0 : 255, light ? 0 : 255, light ? 9 : 6));
        if (key % 12 == 0) { p.setPen(faint); p.drawLine(QPointF(centers[key] - keyWidth / 2,64), QPointF(centers[key] - keyWidth / 2,strike)); }
    }
    for (int second = 0; second <= lookahead; ++second) {
        double y = strike - second * scale; p.setPen(faint); p.drawLine(QPointF(left,y), QPointF(width-right,y));
        text(QString("+%1s").arg(second), {left-32,y+3}, 9, foreground);
    }
    auto time = double(sampleFrame) / 48000.; QList<QJsonObject> notes;
    for (auto value : source) { auto n = value.toObject(); if (n["key"].toInt() >= low && n["key"].toInt() <= high && visible(n["channel"].toInt())) notes << n; }
    std::stable_sort(notes.begin(), notes.end(), [](const auto &a, const auto &b) {
        if (a["start"].toDouble() != b["start"].toDouble()) return a["start"].toDouble() < b["start"].toDouble();
        if (a["channel"].toInt() != b["channel"].toInt()) return a["channel"].toInt() < b["channel"].toInt();
        return a["key"].toInt() < b["key"].toInt();
    });
    const QRectF rain(left,64,width-left-right,strike-64);
    p.save(); p.setClipRect(rain);
    QList<int> active[120];
    for (auto n : notes) {
        auto key = n["key"].toInt(), channel = n["channel"].toInt(); auto start = n["start"].toDouble(), end = n["end"].toDouble();
        if (start <= time && end > time) active[key] << channel;
        if (end <= time || start >= time + lookahead) continue;
        double w = std::max(3., keyWidth * (black(key) ? .52 : .68)), bottom = strike - (start-time)*scale, top = strike-(end-time)*scale;
        QRectF rect(centers[key]-w/2,top,w,std::max(2.,bottom-top)); p.setPen(Qt::NoPen); p.setBrush(channelColor(channel)); p.drawRoundedRect(rect, std::min(3.,w*.15), std::min(3.,w*.15));
        auto intersection = rect.intersected(rain);
        if (w >= 18 && intersection.height() >= 18) text(noteName(key), {rect.left()+2,intersection.bottom()-4},9,QColor(0,0,0,217),w-4);
    }
    p.restore();
    for (bool isBlack : {false,true}) for (auto key : keys) if (black(key) == isBlack) {
        double w = keyWidth*(isBlack?.62:1); QRectF rect(centers[key]-w/2,strike,w,keyboardHeight*(isBlack?.63:1));
        p.fillRect(rect, QColor(isBlack ? "#1a1a1a" : "#e6e6e6"));
        if (!active[key].isEmpty()) {
            auto color = channelColor(active[key].first()); color.setAlphaF(isBlack?.32:.22); p.fillRect(rect,color);
            for (int i = 0; i < active[key].size(); ++i) p.fillRect(QRectF(rect.left()+i*w/active[key].size(),strike,w/active[key].size(),3),channelColor(active[key][i]));
        }
        p.setPen(QPen(QColor(0,0,0,128),.6)); p.setBrush(Qt::NoBrush); p.drawRect(rect);
        if (key%12 == 0 && w>=15) text(noteName(key),{rect.left()+2,rect.bottom()-8},9,QColor(0,0,0,204),w-4);
    }
    p.setPen(QPen(channelColor(0),2)); p.drawLine(QPointF(left,strike),QPointF(width-right,strike));
    const int channels = manifest["channelCount"].toInt(), shown = std::min(channels,std::max(1,(width-80)/38));
    for (int channel=0;channel<shown;++channel) {
        auto color=channelColor(channel); color.setAlphaF(visible(channel)?1:.25); p.setPen(Qt::NoPen); p.setBrush(color);
        p.drawEllipse(QRectF(20+channel*38,height-14,6,6)); text(QString::number(channel+1),{double(30+channel*38),double(height-7)},9,foreground);
    }
}
}

int renderVideo(const QString &path) {
    try {
        std::signal(SIGTERM, interrupted); std::signal(SIGINT, interrupted);
        auto manifest = readJSON(path).object(), options = manifest["options"].toObject();
        const int width = options["width"].toInt(), height = options["height"].toInt(), fps = options["framesPerSecond"].toInt();
        const quint64 audioFrames = manifest["audioFrameCount"].toVariant().toULongLong();
        if (width<320 || width>1920 || height<180 || height>1080 || width%2 || height%2 || !QList<int>{24,25,30,60}.contains(fps) || audioFrames==0 || audioFrames>quint64(3600)*48000) throw std::runtime_error("Ungültige Videooptionen");
        auto executable=QStandardPaths::findExecutable("ffmpeg"); if (executable.isEmpty()) throw std::runtime_error("FFmpeg fehlt");
        QProcess encoder; encoder.setStandardOutputFile(QProcess::nullDevice()); encoder.setStandardErrorFile(QProcess::nullDevice());
        const double bits=options["quality"].toString()=="compact"?.08:.16;
        // FFmpeg darf für die hochauflösende Encoder-Zeitbasis keine Bilder
        // duplizieren; der MOV-Abschluss erwartet genau ein Bild je Schritt.
        encoder.start(executable, {"-v","error","-nostdin","-n","-f","rawvideo","-pixel_format","bgra","-video_size",QString("%1x%2").arg(width).arg(height),"-framerate",QString::number(fps),"-i","pipe:0","-i",manifest["audioPath"].toString(),"-map","0:v:0","-map","1:a:0","-c:v","libx264","-bf","0","-pix_fmt","yuv420p","-b:v",QString::number(std::clamp(int(width*height*fps*bits),600000,24000000)),"-fps_mode","passthrough","-enc_time_base:v","1:48000","-video_track_timescale","48000","-movie_timescale","48000","-c:a","pcm_f32le",manifest["outputPath"].toString()});
        if (!encoder.waitForStarted(5000)) throw std::runtime_error("FFmpeg startet nicht");
        const quint32 step=48000/fps, frames=quint32((audioFrames+step-1)/step);
        QImage image(width,height,QImage::Format_ARGB32); int loaded=-1; QJsonArray notes;
        for (quint32 frame=0;frame<frames;++frame) {
            if (cancelled) { encoder.kill(); encoder.waitForFinished(5000); return 130; }
            int second=int(quint64(frame)*step/48000);
            if (second!=loaded) {
                const auto chunk=manifest["chunksPath"].toString()+"/"+QString::number(second)+".json";
                QElapsedTimer waiting; waiting.start();
                while (!QFile::exists(chunk) && !cancelled && waiting.elapsed()<30000) QThread::msleep(20);
                if (cancelled) { encoder.kill(); encoder.waitForFinished(5000); return 130; }
                notes=readJSON(chunk).array();
                if (!QFile::remove(chunk)) throw std::runtime_error("Notenfenster lässt sich nicht freigeben");
                loaded=second;
            }
            draw(image,manifest,notes,quint64(frame)*step);
            const auto size=qint64(image.sizeInBytes());
            if (encoder.write(reinterpret_cast<const char *>(image.constBits()),size)!=size) throw std::runtime_error("Video-Pipe ist geschlossen");
            QElapsedTimer writing; writing.start();
            while (encoder.bytesToWrite()>0) {
                if (cancelled) { encoder.kill(); encoder.waitForFinished(5000); return 130; }
                if (!encoder.waitForBytesWritten(100) && (encoder.state()==QProcess::NotRunning || writing.elapsed()>30000)) throw std::runtime_error("Videoencoder liefert keine Antwort");
            }
            if (frame%10==0 || frame+1==frames) { QSaveFile progress(manifest["progressPath"].toString()); if (progress.open(QIODevice::WriteOnly)) { progress.write(QByteArray::number(double(frame+1)/frames)); progress.commit(); } }
        }
        encoder.closeWriteChannel();
        QElapsedTimer finishing; finishing.start();
        while (encoder.state()!=QProcess::NotRunning && !cancelled && finishing.elapsed()<30000) encoder.waitForFinished(100);
        if (cancelled || encoder.state()!=QProcess::NotRunning || encoder.exitStatus()!=QProcess::NormalExit || encoder.exitCode()!=0) { encoder.kill(); encoder.waitForFinished(5000); throw std::runtime_error("Videoencoder fehlgeschlagen"); }
        trimLastFrame(manifest["outputPath"].toString(),frames,quint32(audioFrames),step);
        return 0;
    } catch (const std::exception &error) { std::fprintf(stderr,"%s\n",error.what()); return 1; }
}
