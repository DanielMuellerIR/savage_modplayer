#include <QtTest>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QSettings>
#include <QDateTime>
#include "UpdateController.h"

class UpdateTests : public QObject {
    Q_OBJECT
private:
    QString prepare(QTemporaryDir &temp) {
        const auto bundle = temp.path() + "/prefix/lib/savage-mod-player/1.0.0-fixture";
        QDir().mkpath(bundle);
        QFile helper(bundle + "/update.py");
        if (!helper.open(QIODevice::WriteOnly)) return {};
        helper.write(R"PY(import json,sys,time
from pathlib import Path
root=Path(__file__).parent
with (root/'requests').open('a') as log: log.write(sys.argv[-1]+'\n')
if sys.argv[-1]=='check':
 print(json.dumps(dict(event='offer',offer=dict(version='1.0.1',notes='<b>Plain release notes</b>'))),flush=True)
else:
 json.load(sys.stdin)
 print(json.dumps(dict(event='progress',value=.5)),flush=True)
 time.sleep(5 if (root/'wait').exists() else .1)
 print(json.dumps(dict(event='installed',version='1.0.1')),flush=True)
)PY");
        helper.close();
        if (!QFile::link(bundle, QFileInfo(bundle).dir().filePath("current"))) return {};
        return bundle;
    }
private slots:
    void offerInstallAndCancellation() {
        QTemporaryDir temp;
        const auto bundle = prepare(temp); QVERIFY(!bundle.isEmpty());
        UpdateController controller(temp.path(), nullptr, bundle);
        QVERIFY(controller.canInstall());
        controller.setAutomaticallyChecks(false);
        QSignalSpy shown(&controller, &UpdateController::showDialog);
        controller.check(); QVERIFY(controller.busy());
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(shown.count(), 1);
        QCOMPARE(controller.offeredVersion(), QString("1.0.1"));
        QCOMPARE(controller.notes(), QString("<b>Plain release notes</b>"));
        QFile wait(bundle + "/wait"); QVERIFY(wait.open(QIODevice::WriteOnly)); wait.close();
        controller.install();
        QTRY_VERIFY_WITH_TIMEOUT(controller.progress() > 0, 5000);
        controller.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(!controller.installed());
        QVERIFY(controller.status().contains("abgebrochen"));
        QVERIFY(QFile::remove(bundle + "/wait"));
        controller.install();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.installed());
        QVERIFY(!controller.canInstall());
        QVERIFY(controller.status().contains("nächsten Start"));
    }
    void authenticatedPackageInstall() {
        const auto bundle = qEnvironmentVariable("SAVAGE_UPDATE_FIXTURE_BUNDLE");
        if (bundle.isEmpty()) QSKIP("Signed package fixture is provided by linux_update_integration.py");
        QTemporaryDir data;
        UpdateController controller(data.path(), nullptr, bundle);
        controller.setAutomaticallyChecks(false);
        QVERIFY(controller.canInstall());
        controller.check();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 10000);
        QCOMPARE(controller.offeredVersion(), qEnvironmentVariable("SAVAGE_UPDATE_FIXTURE_VERSION"));
        controller.install();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 60000);
        QVERIFY2(controller.installed(), qPrintable(controller.status()));
        QVERIFY(!controller.canInstall());
    }
    void backgroundChecksRespectOptOutAndDailyLimit() {
        QTemporaryDir temp;
        const auto bundle = prepare(temp); QVERIFY(!bundle.isEmpty());
        UpdateController disabled(temp.path()+"/disabled", nullptr, bundle);
        disabled.setAutomaticallyChecks(false);
        QSettings recent(temp.path()+"/recent/updates.ini",QSettings::IniFormat);
        recent.setValue("lastCheck",QDateTime::currentSecsSinceEpoch()); recent.sync();
        UpdateController limited(temp.path()+"/recent",nullptr,bundle);
        UpdateController automatic(temp.path()+"/automatic",nullptr,bundle);
        QSignalSpy offered(&automatic,&UpdateController::showDialog);
        QTRY_COMPARE_WITH_TIMEOUT(offered.count(),1,5000);
        QFile requests(bundle+"/requests"); QVERIFY(requests.open(QIODevice::ReadOnly));
        QCOMPARE(requests.readAll(),QByteArray("check\n"));
        QTRY_VERIFY_WITH_TIMEOUT(!automatic.busy(), 1000);
    }
};
QTEST_GUILESS_MAIN(UpdateTests)
#include "qt_update_tests.moc"
