#ifndef DSHBRIDGE_H
#define DSHBRIDGE_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QtQml/qqml.h>

// 供 QML Plasmoid 使用的最小桥接类型：
//  - submit(question, effort): 通过 org.dsh.widget 的 D-Bus 把问题送进 DSH 输入框
//  - getSummary(): 读取后台脚本写好的本地 JSON 摘要文件
// 全部用 QProcess/gdbus，避免 QDBus 类型注册与 Qt 版本差异带来的复杂度。
class DshBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit DshBridge(QObject *parent = nullptr);

    Q_INVOKABLE void submit(const QString &question, const QString &effort);
    Q_INVOKABLE QString getSummary() const;
    Q_INVOKABLE bool dshOnline() const;
    Q_INVOKABLE void openDsh();

signals:
    void submitted(bool ok, const QString &message);

private:
    QString summaryPath() const;
};

#endif // DSHBRIDGE_H
