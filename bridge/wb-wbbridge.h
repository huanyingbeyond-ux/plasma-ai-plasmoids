#ifndef WBBRIDGE_H
#define WBBRIDGE_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QtQml/qqml.h>

// 供 WorkBuddy KDE Plasmoid 使用的最小桥接类型。
//  - openDeepLink(url): 通过 workbuddy <深链> 唤起对应功能页（新对话/任务/技能…）
//  - openWorkBuddy():   打开 WorkBuddy 主窗口
//  - wbOnline():        检测 workbuddy 是否有可见窗口（X 的 WM_CLASS）
// 只读 + 启动器，不注入任何输入到闭源 Electron 内部。
class WbBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit WbBridge(QObject *parent = nullptr);

    Q_INVOKABLE void openDeepLink(const QString &url);
    Q_INVOKABLE void openWorkBuddy();
    Q_INVOKABLE bool wbOnline() const;

signals:
    void opened(bool ok, const QString &message);
};

#endif // WBBRIDGE_H
