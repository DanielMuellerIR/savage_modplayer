#include "MediaControls.h"
#include <QCoreApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QUrl>
#include <QCryptographicHash>
#include <cmath>

class MediaRoot final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes)
    Q_PROPERTY(bool CanRaise READ yes)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ schemes)
    Q_PROPERTY(QStringList SupportedMimeTypes READ mimeTypes)
public:
    MediaControls *owner;
    explicit MediaRoot(MediaControls *owner) : QDBusAbstractAdaptor(owner), owner(owner) {}
    bool yes() const { return true; } bool no() const { return false; }
    QString identity() const { return "Savage Mod Player"; }
    QString desktopEntry() const { return "savage-mod-player"; }
    QStringList schemes() const { return {"file"}; }
    QStringList mimeTypes() const { return {"audio/x-mod","audio/x-s3m","audio/x-xm","audio/x-it"}; }
public slots:
    void Raise() { emit owner->raiseRequested(); }
    void Quit() { QCoreApplication::quit(); }
};

class MediaPlayer final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ status)
    Q_PROPERTY(QString LoopStatus READ loop WRITE setLoop)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ rate)
    Q_PROPERTY(double MaximumRate READ rate)
    Q_PROPERTY(bool CanGoNext READ hasTrack)
    Q_PROPERTY(bool CanGoPrevious READ hasTrack)
    Q_PROPERTY(bool CanPlay READ hasTrack)
    Q_PROPERTY(bool CanPause READ hasTrack)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ yes)
public:
    MediaControls *owner;
    explicit MediaPlayer(MediaControls *owner) : QDBusAbstractAdaptor(owner), owner(owner) {}
    bool yes() const { return true; }
    bool hasTrack() const { return owner->module.contains("title"); }
    bool canSeek() const { return hasTrack(); }
    QString trackPath() const { return "/org/mpris/MediaPlayer2/track_"+QString::fromLatin1(QCryptographicHash::hash(owner->module.value("revision").toByteArray(),QCryptographicHash::Sha256).toHex()); }
    QString status() const { return !owner->state.value("playing").toBool() ? "Stopped" : (owner->state.value("paused").toBool() ? "Paused" : "Playing"); }
    QString loop() const { auto value=owner->preferences.value("loop","playlist").toString(); return value=="track"?"Track":(value=="none"?"None":"Playlist"); }
    void setLoop(const QString &value) { if (QStringList{"Track","Playlist","None"}.contains(value)) owner->command("option",{{"text","loop"},{"setting",value=="Track"?"track":(value=="None"?"none":"playlist")}}); }
    double rate() const { return 1; } void setRate(double) {}
    bool shuffle() const { return owner->preferences.value("shuffle").toBool(); }
    void setShuffle(bool value) { owner->command("option",{{"text","shuffle"},{"setting",value}}); }
    double volume() const { return owner->preferences.value("volume",.6).toDouble(); }
    void setVolume(double value) { if (std::isfinite(value)) owner->command("volume",{{"value",qBound(0.,value,1.)}}); }
    qlonglong position() const { return qlonglong(owner->state.value("elapsed").toDouble()*1000000); }
    QVariantMap metadata() const {
        if (!hasTrack()) return {};
        return {{"mpris:trackid",QVariant::fromValue(QDBusObjectPath(trackPath()))},
                {"mpris:length",qlonglong(owner->state.value("duration").toDouble()*1000000)},
                {"xesam:title",owner->module.value("title")},{"xesam:url",owner->module.value("fileURL")}};
    }
public slots:
    void Play() { owner->command("resume",{}); }
    void Pause() { owner->command("pause",{}); }
    void PlayPause() { owner->command("play",{}); }
    void Stop() { owner->command("stop",{}); }
    void Next() { owner->command("next",{}); }
    void Previous() { owner->command("previous",{}); }
    void Seek(qlonglong offset) { owner->command("seekSeconds",{{"value",double(offset)/1000000}}); }
    void SetPosition(const QDBusObjectPath &track, qlonglong position) {
        if (track.path()==trackPath() && position>=0) owner->command("seekSeconds",{{"value",double(position)/1000000-owner->state.value("elapsed").toDouble()}});
    }
    void OpenUri(const QString &uri) { QUrl url(uri); if (url.isLocalFile()) owner->command("open",{{"paths",QStringList{url.toLocalFile()}}}); }
};

MediaControls::MediaControls(std::function<void(QString,QVariantMap)> command, QObject *parent) : QObject(parent), command(std::move(command)) {
    new MediaRoot(this); new MediaPlayer(this);
    auto bus=QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        bus.registerService("org.mpris.MediaPlayer2.savage.desktop"+QString::number(QCoreApplication::applicationPid()));
        bus.registerObject("/org/mpris/MediaPlayer2",this,QDBusConnection::ExportAdaptors);
    }
}
void MediaControls::update(const QString &event,const QVariantMap &values) {
    const double previousDuration = state.value("duration").toDouble();
    QString previousStatus=state.value("playing").toBool()?(state.value("paused").toBool()?"Paused":"Playing"):"Stopped";
    if (event=="state") state=values;
    else if (event=="module") module=values;
    else if (event=="preferences") preferences=values;
    else if (event=="ready") preferences=values.value("preferences").toMap();
    else return;
    auto player=findChild<MediaPlayer *>(); QVariantMap changed;
    if (event=="module" || previousDuration != state.value("duration").toDouble()) changed["Metadata"]=player->metadata();
    if (event=="preferences" || event=="ready") { changed["Volume"]=player->volume(); changed["LoopStatus"]=player->loop(); changed["Shuffle"]=player->shuffle(); }
    if (previousStatus!=player->status()) changed["PlaybackStatus"]=player->status();
    if (!changed.isEmpty()) {
        auto signal=QDBusMessage::createSignal("/org/mpris/MediaPlayer2","org.freedesktop.DBus.Properties","PropertiesChanged");
        signal << QString("org.mpris.MediaPlayer2.Player") << changed << QStringList{};
        QDBusConnection::sessionBus().send(signal);
    }
}
#include "MediaControls.moc"
