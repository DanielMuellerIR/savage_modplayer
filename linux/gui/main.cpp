#include <QApplication>
#include <QCommandLineParser>
#include <QDesktopServices>
#include <QDir>
#include <QFileDialog>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <cstdio>
#include <QProcess>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QCryptographicHash>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QMessageBox>
#include <QIcon>
#include <QSettings>
#include <QScreen>
#include <csignal>
#include <memory>
#include "VideoRenderer.h"
#include "MediaControls.h"
#include "UpdateController.h"

static volatile std::sig_atomic_t terminateRequested = 0;
static void requestTermination(int) { terminateRequested = 1; }

class DesktopBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state MEMBER state NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap visualizer MEMBER visualizer NOTIFY visualizerChanged)
    Q_PROPERTY(QVariantMap module MEMBER module NOTIFY moduleChanged)
    Q_PROPERTY(QVariantMap library MEMBER library NOTIFY libraryChanged)
    Q_PROPERTY(QVariantMap preferences MEMBER preferences NOTIFY preferencesChanged)
    Q_PROPERTY(QVariantMap pattern MEMBER pattern NOTIFY patternChanged)
    Q_PROPERTY(QVariantMap notes MEMBER notes NOTIFY notesChanged)
public:
    QVariantMap visualizer;
    QVariantMap state, module, library, preferences, pattern, notes;
    QVariantMap pendingLibrary;
    QVariantList pendingTracks, pendingVisible;
    QProcess process;
    QByteArray buffered;
    QStringList startupPaths;
    bool captureStopped = false;
    QString confirmedOverwrite;
    explicit DesktopBridge(QObject *parent = nullptr) : QObject(parent) {
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
            buffered += process.readAllStandardOutput();
            if (buffered.size() > 32 * 1024 * 1024) { process.kill(); emit message("error", {{"message", "Desktop-Antwort überschreitet die Größenbegrenzung."}}); return; }
            while (true) {
                auto newline = buffered.indexOf('\n');
                if (newline < 0) break;
                auto data = buffered.left(newline); buffered.remove(0, newline + 1);
                auto document = QJsonDocument::fromJson(data);
                if (!document.isObject()) continue;
                auto values = document.object().toVariantMap();
                auto event = values.value("event").toString();
                if (event == "state") { if (state != values) { state = values; emit stateChanged(); } }
                else if (event == "visualizer") { visualizer = values; emit visualizerChanged(); continue; }
                else if (event == "module") { module = values; emit moduleChanged(); }
                else if (event == "libraryBegin") { pendingLibrary = values; pendingTracks.clear(); pendingVisible.clear(); }
                else if (event == "libraryTracks") pendingTracks += values.value("tracks").toList();
                else if (event == "libraryVisible") pendingVisible += values.value("ids").toList();
                else if (event == "libraryEnd") {
                    pendingLibrary["tracks"] = pendingTracks; pendingLibrary["visible"] = pendingVisible;
                    library = pendingLibrary; emit libraryChanged(); emit message("library", library);
                }
                else if (event == "pattern") { pattern = values; emit patternChanged(); }
                else if (event == "notes") { notes = values; emit notesChanged(); }
                else if (event == "preferences" || event == "ready") {
                    if (event == "ready") ready = true;
                    preferences = event == "ready" ? values.value("preferences").toMap() : values;
                    emit preferencesChanged();
                    if (event == "ready" && !startupPaths.isEmpty()) send({{"command", "open"}, {"paths", startupPaths}, {"autoPlay",!captureStopped}});
                }
                emit message(event, values);
            }
        });
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            emit message("error", {{"message", "Die Wiedergabe-Engine konnte nicht gestartet werden: " + process.errorString()}});
        });
        connect(&process, &QProcess::readyReadStandardError, this, [this] { process.readAllStandardError(); });
        connect(&process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this](int code, QProcess::ExitStatus status) {
            if (!closing) emit message("error", {{"message", QString("Die Wiedergabe-Engine wurde beendet (%1). Bitte die App neu starten.").arg(code)}, {"crash", status == QProcess::CrashExit}});
        });
    }
    void start(const QString &executable) { process.start(executable, {}); }
    Q_INVOKABLE void send(const QVariantMap &values) {
        if (!ready && values.value("command") == "open") { startupPaths = values.value("paths").toStringList(); return; }
        if (process.state() != QProcess::Running) return;
        process.write(QJsonDocument(QJsonObject::fromVariantMap(values)).toJson(QJsonDocument::Compact) + '\n');
    }
    Q_INVOKABLE void command(const QString &name, const QVariantMap &parameters = {}) {
        auto values = parameters; values["command"] = name; send(values);
    }
    Q_INVOKABLE void option(const QString &name, const QVariant &value) { command("option", {{"text", name}, {"setting", value}}); }
    Q_INVOKABLE void open(bool folder = false) {
        QStringList paths;
        if (folder) {
            auto path = QFileDialog::getExistingDirectory(nullptr, "Musikordner öffnen");
            if (!path.isEmpty()) paths << path;
        } else paths = QFileDialog::getOpenFileNames(nullptr, "Module oder Archive öffnen", {}, "Tracker-Module und Archive (*.mod *.MOD *.s3m *.S3M *.xm *.XM *.it *.IT *.zip *.7z *.savagecollection);;Alle Dateien (*)");
        if (!paths.isEmpty()) command("open", {{"paths", paths}, {"autoPlay",false}});
    }
    Q_INVOKABLE void drop(const QVariantList &urls) {
        QStringList paths;
        for (auto value : urls) { QUrl url(value.toString()); if (url.isLocalFile()) paths << url.toLocalFile(); }
        if (!paths.isEmpty()) command("open", {{"paths", paths}});
    }
    Q_INVOKABLE QString chooseFolder(const QString &title) { return QFileDialog::getExistingDirectory(nullptr, title); }
    Q_INVOKABLE void importCollection() {
        auto path = QFileDialog::getOpenFileName(nullptr, "Sammlung importieren", {}, "Savage-Sammlung (*.savagecollection)");
        if (!path.isEmpty()) command("collectionImport", {{"path", path}});
    }
    Q_INVOKABLE QString saveFile(const QString &title, const QString &name, const QString &filter, bool allowOverwrite = false) {
        auto path = QFileDialog::getSaveFileName(nullptr, title, name, filter, nullptr,
            allowOverwrite ? QFileDialog::Options{} : QFileDialog::Options{QFileDialog::DontConfirmOverwrite});
        confirmedOverwrite = allowOverwrite && QFileInfo::exists(path) ? path : QString{};
        return path;
    }
    Q_INVOKABLE bool overwriteApproved(const QString &path) const { return !path.isEmpty() && path == confirmedOverwrite; }
    Q_INVOKABLE void reveal(const QString &path) { QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).isDir() ? path : QFileInfo(path).absolutePath())); }
    Q_INVOKABLE QUrl fileURL(const QString &path) { return QUrl::fromLocalFile(path); }
    Q_INVOKABLE void shutdown() {
        if (closing) return; closing = true;
        command("quit"); process.closeWriteChannel();
        if (!process.waitForFinished(3000)) { process.terminate(); if (!process.waitForFinished(1000)) { process.kill(); process.waitForFinished(); } }
    }
signals:
    void visualizerChanged();
    void stateChanged(); void moduleChanged(); void libraryChanged(); void preferencesChanged();
    void patternChanged(); void notesChanged();
    void message(const QString &event, const QVariantMap &values);
private:
    bool closing = false;
    bool ready = false;
};

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    if (argc == 3 && QString::fromLocal8Bit(argv[1]) == "--render-video") return renderVideo(QString::fromLocal8Bit(argv[2]));
    std::signal(SIGTERM, requestTermination); std::signal(SIGINT, requestTermination);
    QTimer terminationTimer;
    QObject::connect(&terminationTimer, &QTimer::timeout, &app, [&] { if (terminateRequested) app.quit(); });
    terminationTimer.start(100);
    app.setApplicationName("Savage Mod Player"); app.setOrganizationName("Savage Mod Player");
    app.setApplicationVersion(SAVAGE_VERSION);
    app.setWindowIcon(QIcon(":/AppIcon.png"));
    QQuickStyle::setStyle("Basic");
    QCommandLineParser parser; parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption({"engine", "Pfad zur Swift-Engine", "path"});
    parser.addOption({"screenshot", "Headless-Prüfbild speichern und beenden", "path"});
    parser.addOption({"capture-delay", "Prüfaufnahme nach Millisekunden", "milliseconds", "2000"});
    parser.addOption({"review-view", "Ansicht für eine Headless-Prüfaufnahme", "name"});
    parser.addPositionalArgument("files", "Moduldateien, Ordner oder Archive", "[files…]");
    parser.process(app);
    QString dataPath = qEnvironmentVariable("SAVAGE_DESKTOP_DATA");
    if (dataPath.isEmpty()) dataPath = qEnvironmentVariable("XDG_DATA_HOME", QDir::homePath()+"/.local/share")+"/savage-mod-player";
    if (!QDir().mkpath(dataPath)) { QMessageBox::critical(nullptr,"Savage Mod Player","Das Datenverzeichnis lässt sich nicht anlegen."); return 2; }
    const auto instanceName = "savage-mod-player-" + QString::fromLatin1(QCryptographicHash::hash(QFileInfo(dataPath).canonicalFilePath().toUtf8(),QCryptographicHash::Sha256).toHex().left(20));
    QStringList paths;
    for (auto path : parser.positionalArguments()) paths << QFileInfo(path).absoluteFilePath();
    auto notifyExisting = [&] {
        QLocalSocket socket; socket.connectToServer(instanceName);
        if (!socket.waitForConnected(300)) return false;
        socket.write(QJsonDocument(QJsonObject{{"paths",QJsonArray::fromStringList(paths)}}).toJson(QJsonDocument::Compact)+'\n');
        socket.waitForBytesWritten(1000); socket.disconnectFromServer(); return true;
    };
    if (notifyExisting()) return 0;
    QLockFile instanceLock(dataPath+"/desktop.lock");
    if (!instanceLock.tryLock(1500)) {
        if (notifyExisting()) return 0;
        QMessageBox::critical(nullptr,"Savage Mod Player","Eine andere Instanz verwendet bereits diese Sammlung."); return 2;
    }
    QLocalServer::removeServer(instanceName);
    QLocalServer server; server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!server.listen(instanceName)) return 2;
    DesktopBridge bridge;
    bridge.startupPaths = paths;
    bridge.captureStopped = parser.isSet("screenshot") && parser.value("review-view") != "signals";
    MediaControls media([&bridge](const QString &command, const QVariantMap &values) { bridge.command(command, values); });
    QObject::connect(&bridge, &DesktopBridge::message, &media, &MediaControls::update);
    UpdateController updates(dataPath);
    QQmlApplicationEngine interface;
    QStringList interfaceErrors;
    QObject::connect(&interface,&QQmlEngine::warnings,&interface,[&](const QList<QQmlError> &errors) {
        for (const auto &error : errors) { interfaceErrors << error.toString(); std::fprintf(stderr,"%s\n",qPrintable(error.toString())); }
    });
    interface.rootContext()->setContextProperty("desktop", &bridge);
    interface.rootContext()->setContextProperty("desktopVersion", app.applicationVersion());
    interface.rootContext()->setContextProperty("desktopUpdates", &updates);
    interface.load(QUrl("qrc:/Main.qml"));
    if (interface.rootObjects().isEmpty()) {
        if (!parser.isSet("screenshot")) QMessageBox::critical(nullptr,"Savage Mod Player",
            "Die Oberfläche konnte nicht geladen werden. Bitte die Qt-QML-Laufzeitmodule prüfen.\n\n"+interfaceErrors.join('\n'));
        return 1;
    }
    auto mainWindow = qobject_cast<QQuickWindow *>(interface.rootObjects().first());
    if (!parser.isSet("screenshot")) {
        QSettings settings(dataPath+"/window.ini",QSettings::IniFormat);
        auto saved = settings.value("mainGeometry").toRect();
        if (saved.isValid()) {
            const auto available = mainWindow->screen()->availableGeometry();
            saved.setSize(saved.size().boundedTo(available.size()).expandedTo(mainWindow->minimumSize()));
            saved.moveLeft(qBound(available.left(),saved.left(),qMax(available.left(),available.right()-saved.width()+1)));
            saved.moveTop(qBound(available.top(),saved.top(),qMax(available.top(),available.bottom()-saved.height()+1)));
            mainWindow->setGeometry(saved);
        }
        if (settings.value("maximized",false).toBool()) mainWindow->showMaximized();
        QObject::connect(&app,&QCoreApplication::aboutToQuit,&interface,[&,mainWindow] {
            QSettings settings(dataPath+"/window.ini",QSettings::IniFormat);
            if (mainWindow->visibility()!=QWindow::Maximized) settings.setValue("mainGeometry",mainWindow->geometry());
            settings.setValue("maximized",mainWindow->visibility()==QWindow::Maximized);
        });
    }
    QObject::connect(&server,&QLocalServer::newConnection,&interface,[&] {
        while (auto socket=server.nextPendingConnection()) {
            QObject::connect(socket,&QLocalSocket::disconnected,socket,&QObject::deleteLater);
            auto receive = [&,socket] {
                auto data=socket->property("payload").toByteArray()+socket->readAll();
                if (data.size()>1024*1024) { socket->abort(); return; }
                if (!data.contains('\n')) { socket->setProperty("payload",data); return; }
                auto incoming=QJsonDocument::fromJson(data.left(data.indexOf('\n'))).object().value("paths").toArray();
                QStringList files; for(auto value:incoming)if(value.isString())files<<value.toString();
                if(!files.isEmpty())bridge.command("open",{{"paths",files}});
                auto window=qobject_cast<QQuickWindow *>(interface.rootObjects().first());window->show();window->raise();window->requestActivate();
                socket->disconnectFromServer();
            };
            QObject::connect(socket,&QLocalSocket::readyRead,&interface,receive);
            if (socket->bytesAvailable()) receive();
        }
    });
    QObject::connect(&media, &MediaControls::raiseRequested, &interface, [&] { auto window = qobject_cast<QQuickWindow *>(interface.rootObjects().first()); window->show(); window->raise(); window->requestActivate(); });
    const auto enginePath = parser.isSet("engine") ? parser.value("engine") : QCoreApplication::applicationDirPath() + "/savage-desktop-engine";
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert("SAVAGE_VIDEO_RENDERER", QCoreApplication::applicationFilePath());
    bridge.process.setProcessEnvironment(environment);
    bridge.start(enginePath);
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &bridge, &DesktopBridge::shutdown);
    if (parser.isSet("screenshot")) {
        auto reviewed = std::make_shared<bool>(false);
        auto review = [&, reviewed] {
            if (*reviewed || !parser.isSet("review-view")) return;
            *reviewed = true;
            QMetaObject::invokeMethod(interface.rootObjects().first(),"reviewView",Q_ARG(QVariant,parser.value("review-view")));
        };
        QObject::connect(&bridge, &DesktopBridge::moduleChanged, &interface, [&, review] { QTimer::singleShot(100,&interface,review); });
        if (paths.isEmpty()) QTimer::singleShot(600,&interface,review);
        QTimer::singleShot(qBound(100, parser.value("capture-delay").toInt(), 30000), &app, [&] {
            auto window = qobject_cast<QQuickWindow *>(interface.rootObjects().first());
            if(parser.value("review-view")=="noteRain")window=interface.rootObjects().first()->findChild<QQuickWindow *>("noteRainWindow");
            QJsonArray layout;
            for (auto item : interface.rootObjects().first()->findChildren<QQuickItem *>()) if (QStringList{"sidebarLayout","playlistList","recentSection","recentList","channelScopes"}.contains(item->objectName())) {
                const auto point = item->mapToScene({0,0});
                layout.append(QJsonObject{{"name", item->objectName()}, {"x", point.x()}, {"y", point.y()}, {"width", item->width()}, {"height", item->height()}, {"visible", item->isVisible()}, {"count",item->property("count").toInt()}});
            }
            QFile report(parser.value("screenshot") + ".json");
            if (report.open(QIODevice::WriteOnly)) report.write(QJsonDocument(layout).toJson());
            const auto picture = window ? window->grabWindow() : QImage();
            app.exit(picture.isNull() || !picture.save(parser.value("screenshot")) ? 2 : 0);
        });
    }
    return app.exec();
}
#include "main.moc"
