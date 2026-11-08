#include "UpdateController.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcessEnvironment>
#include <QStandardPaths>

UpdateController::UpdateController(const QString &dataPath, QObject *parent, const QString &bundlePath)
    : QObject(parent), bundle(bundlePath.isEmpty() ? QCoreApplication::applicationDirPath() : bundlePath),
      settings(dataPath + "/updates.ini", QSettings::IniFormat) {
    message = "Installiert: " + QCoreApplication::applicationVersion();
    connect(&worker, &QProcess::readyReadStandardOutput, this, &UpdateController::consumeOutput);
    connect(&worker, &QProcess::readyReadStandardError, this, [this] { worker.readAllStandardError(); });
    connect(&worker, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            running = false;
            message = "Die Updateprüfung benötigt Python 3 und OpenSSL 3.";
            emit changed();
        }
    });
    connect(&worker, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int, QProcess::ExitStatus) {
            consumeOutput();
            running = false;
            if (!receivedResult) message = "Die Aktualisierung wurde abgebrochen oder konnte nicht abgeschlossen werden.";
            emit changed();
        });
    daily.setInterval(24 * 60 * 60 * 1000);
    connect(&daily, &QTimer::timeout, this, &UpdateController::automaticCheck);
    daily.start();
    QTimer::singleShot(3000, this, &UpdateController::automaticCheck);
}

UpdateController::~UpdateController() {
    if (worker.state() != QProcess::NotRunning) {
        worker.terminate();
        if (!worker.waitForFinished(5000)) { worker.kill(); worker.waitForFinished(1000); }
    }
}

bool UpdateController::automaticallyChecks() const { return settings.value("automatic", true).toBool(); }
void UpdateController::setAutomaticallyChecks(bool enabled) {
    settings.setValue("automatic", enabled);
    emit changed();
}

bool UpdateController::canInstall() const {
    const QDir root = QFileInfo(bundle).dir();
    const QFileInfo current(root.filePath("current"));
    return !activated && root.dirName() == "savage-mod-player" && QFileInfo(root.absolutePath()).dir().dirName() == "lib"
        && current.isSymLink() && current.canonicalFilePath() == QFileInfo(bundle).canonicalFilePath()
        && QFileInfo::exists(bundle + "/update.py");
}

void UpdateController::automaticCheck() {
    const auto now = QDateTime::currentSecsSinceEpoch();
    if (!running && canInstall() && automaticallyChecks()
        && now - settings.value("lastCheck", 0).toLongLong() >= 24 * 60 * 60) start("check", true);
}

void UpdateController::check() {
    emit showDialog();
    if (!running && !activated) start("check", false);
}

void UpdateController::install() {
    if (!running && canInstall() && !offer.isEmpty()) start("install", false);
}

void UpdateController::cancel() {
    if (running) { message = "Aktualisierung wird abgebrochen …"; worker.terminate(); emit changed(); }
}

void UpdateController::start(const QString &action, bool isAutomatic) {
    const auto python = QStandardPaths::findExecutable("python3");
    if (python.isEmpty() || !QFileInfo::exists(bundle + "/update.py")) {
        message = "Bitte diese Version zuerst mit install.sh installieren. Updates benötigen Python 3 und OpenSSL 3.";
        emit changed(); return;
    }
    automatic = isAutomatic;
    receivedResult = false;
    buffered.clear();
    fraction = 0;
    running = true;
    if (action == "check") {
        offer = {};
        settings.setValue("lastCheck", QDateTime::currentSecsSinceEpoch());
        message = "Signierte Updatebeschreibung wird geprüft …";
    } else message = "Update wird geladen und geprüft. Die Wiedergabe läuft weiter …";
    emit changed();
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert("PYTHONDONTWRITEBYTECODE", "1");
    worker.setProcessEnvironment(environment);
    worker.start(python, {bundle + "/update.py", "--bundle", bundle, "--action", action});
    if (action == "install") worker.write(QJsonDocument(offer).toJson(QJsonDocument::Compact));
    worker.closeWriteChannel();
}

void UpdateController::consumeOutput() {
    buffered += worker.readAllStandardOutput();
    if (buffered.size() > 1024 * 1024) { worker.kill(); return; }
    while (true) {
        const auto newline = buffered.indexOf('\n');
        if (newline < 0) break;
        auto line = buffered.left(newline); buffered.remove(0, newline + 1);
        if (line.size() > 65536) { worker.kill(); return; }
        const auto value = QJsonDocument::fromJson(line).object();
        const auto event = value.value("event").toString();
        if (event == "progress") fraction = qBound(0., value.value("value").toDouble(), 1.);
        else if (event == "offer") {
            receivedResult = true;
            offer = value.value("offer").toObject();
            message = offer.isEmpty() ? "Diese Version ist aktuell."
                : "Version " + offeredVersion() + " ist verfügbar.";
            if (!offer.isEmpty() && !canInstall()) message += " Bitte diese Version zunächst mit install.sh installieren.";
            if (automatic && !offer.isEmpty()) emit showDialog();
        } else if (event == "installed") {
            receivedResult = true;
            activated = true;
            fraction = 1;
            message = "Version " + value.value("version").toString() + " ist installiert. Sie wird beim nächsten Start verwendet. Die Wiedergabe kann weiterlaufen.";
        } else if (event == "error") {
            receivedResult = true;
            message = value.value("message").toString();
        }
        emit changed();
    }
}
