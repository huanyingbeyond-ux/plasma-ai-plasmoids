#include "wbbridge.h"

#include <QDebug>

WbBridge::WbBridge(QObject *parent)
    : QObject(parent)
{
}

void WbBridge::openDeepLink(const QString &url)
{
    if (url.trimmed().isEmpty()) {
        emit opened(false, QStringLiteral("深链为空"));
        return;
    }
    // /usr/bin/workbuddy 是官方 wrapper：exec /opt/WorkBuddy/workbuddy "$@"
    // 传 workbuddy://chat 等深链即可唤起对应页面。
    const bool ok = QProcess::startDetached(
        QStringLiteral("/usr/bin/workbuddy"), QStringList{ url });
    qDebug() << "[wb-plasmoid] openDeepLink" << url << (ok ? "OK" : "FAIL");
    emit opened(ok, ok ? QStringLiteral("已唤起 WorkBuddy") : QStringLiteral("启动失败"));
}

void WbBridge::openWorkBuddy()
{
    openDeepLink(QStringLiteral("workbuddy://home"));
}

bool WbBridge::wbOnline() const
{
    // 用 X 的窗口列表检测：WM_CLASS 含 "workbuddy" 即认为在运行。
    // xprop -root _NET_CLIENT_LIST 列出所有窗口 id，逐个查 WM_CLASS。
    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(QStringLiteral("bash"), {
        QStringLiteral("-c"),
        QStringLiteral(
            "for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do "
            "  xprop -id \"$w\" WM_CLASS 2>/dev/null | grep -qi 'workbuddy' && echo FOUND && break; "
            "done")
    });
    proc.waitForFinished(1500);
    return QString::fromUtf8(proc.readAllStandardOutput()).contains(QStringLiteral("FOUND"));
}
