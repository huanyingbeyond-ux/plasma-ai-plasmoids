#include "dshbridge.h"

#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QDebug>

DshBridge::DshBridge(QObject *parent)
    : QObject(parent)
{
}

QString DshBridge::summaryPath() const
{
    // 后台脚本定时把最近问答摘要写到用户状态目录
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation))
        .filePath(QStringLiteral("dsh-widget/summary.json"));
}

void DshBridge::submit(const QString &question, const QString &effort)
{
    if (question.trimmed().isEmpty()) {
        emit submitted(false, QStringLiteral("问题为空"));
        return;
    }

    // 用 gdbus 直接调用已打通的 org.dsh.widget.SubmitQuestion。
    // bash 侧负责在 DSH 未开时拉起窗口（dbus 名出现后再调），这里只做调用。
    const QStringList args {
        QStringLiteral("call"), QStringLiteral("--session"),
        QStringLiteral("--dest"), QStringLiteral("org.dsh.widget"),
        QStringLiteral("--object-path"), QStringLiteral("/org/dsh/widget"),
        QStringLiteral("--method"), QStringLiteral("org.dsh.widget.SubmitQuestion"),
        question, effort
    };

    auto *proc = new QProcess(this);
    proc->setProgram(QStringLiteral("gdbus"));
    proc->setArguments(args);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
                const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
                const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
                const bool ok = (exitCode == 0);
                qDebug() << "[dsh-plasmoid] submit" << (ok ? "OK" : "FAIL") << out << err;
                emit submitted(ok, ok ? QStringLiteral("已送入 DSH 输入框") : err);
                proc->deleteLater();
            });
    proc->start();
}

QString DshBridge::getSummary() const
{
    QFile f(summaryPath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(f.readAll());
}

bool DshBridge::dshOnline() const
{
    QProcess proc;
    proc.start(QStringLiteral("gdbus"), {
        QStringLiteral("call"), QStringLiteral("--session"),
        QStringLiteral("--dest"), QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("--object-path"), QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("--method"), QStringLiteral("org.freedesktop.DBus.NameHasOwner"),
        QStringLiteral("org.dsh.widget")
    });
    proc.waitForFinished(1500);
    return QString::fromUtf8(proc.readAllStandardOutput()).contains(QStringLiteral("true"));
}

void DshBridge::openDsh()
{
    const QString launcher = QDir::home().filePath(QStringLiteral(".local/bin/dsh-native"));
    QProcess::startDetached(launcher, {});
}
