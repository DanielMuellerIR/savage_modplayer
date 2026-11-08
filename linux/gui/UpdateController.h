#pragma once
#include <QObject>
#include <QJsonObject>
#include <QProcess>
#include <QSettings>
#include <QTimer>

class UpdateController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool automaticallyChecks READ automaticallyChecks WRITE setAutomaticallyChecks NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool canInstall READ canInstall NOTIFY changed)
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    Q_PROPERTY(double progress READ progress NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString offeredVersion READ offeredVersion NOTIFY changed)
    Q_PROPERTY(QString notes READ notes NOTIFY changed)
public:
    explicit UpdateController(const QString &dataPath, QObject *parent = nullptr, const QString &bundlePath = QString());
    ~UpdateController() override;
    bool automaticallyChecks() const;
    void setAutomaticallyChecks(bool enabled);
    bool busy() const { return running; }
    bool canInstall() const;
    bool installed() const { return activated; }
    double progress() const { return fraction; }
    QString status() const { return message; }
    QString offeredVersion() const { return offer.value("version").toString(); }
    QString notes() const { return offer.value("notes").toString(); }
    Q_INVOKABLE void check();
    Q_INVOKABLE void install();
    Q_INVOKABLE void cancel();
signals:
    void changed();
    void showDialog();
private:
    void automaticCheck();
    void start(const QString &action, bool automatic);
    void consumeOutput();
    QString bundle;
    QSettings settings;
    QProcess worker;
    QTimer daily;
    QByteArray buffered;
    QJsonObject offer;
    bool running = false, activated = false, automatic = false, receivedResult = false;
    double fraction = 0;
    QString message;
};
