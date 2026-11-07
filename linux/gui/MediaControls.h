#pragma once
#include <QObject>
#include <QVariantMap>
#include <functional>

class MediaControls final : public QObject {
    Q_OBJECT
public:
    explicit MediaControls(std::function<void(QString,QVariantMap)> command, QObject *parent = nullptr);
    QVariantMap state, module, preferences;
    std::function<void(QString,QVariantMap)> command;
    void update(const QString &event, const QVariantMap &values);
signals:
    void raiseRequested();
};
