#pragma once

#include <QByteArray>
#include <QDebug>
#include <QProcess>

class ProcessErrorTail {
public:
    void clear() { bytes.clear(); }

    void read(QProcess &process) {
        constexpr qsizetype limit = 4096;
        bytes.append(process.readAllStandardError().right(limit));
        if (bytes.size() > limit)
            bytes.remove(0, bytes.size() - limit);
    }

    void report(QProcess &process, const char *source) {
        read(process);
        if (!bytes.trimmed().isEmpty())
            qWarning().noquote() << source << QString::fromUtf8(bytes).trimmed();
    }

private:
    QByteArray bytes;
};
