import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "org/dean/wb" as Wb

// WorkBuddy 小态：只显示积分 + 用量
PlasmoidItem {
    id: root

    property double cfg_fontScale: Plasmoid.configuration.fontScale || 1.0
    property int cfg_refreshSeconds: Plasmoid.configuration.refreshSeconds || 8
    readonly property real fs: cfg_fontScale
    readonly property color brand: "#16A34A"

    property var dataObj: ({})
    property bool online: false

    Wb.WbBridge { id: bridge }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.icon: "workbuddy"
    Plasmoid.title: "WorkBuddy 积分用量"
    toolTipMainText: "WorkBuddy 积分与用量"
    toolTipSubText: "累计积分 " + root.num(root.dataObj.creditSpent) + " · 上下文 " + (root.dataObj.usagePercent || 0) + "%"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "打开 WorkBuddy"
            icon.name: "open-external"
            onTriggered: bridge.openWorkBuddy()
        },
        PlasmaCore.Action {
            text: "刷新"
            icon.name: "view-refresh"
            onTriggered: root.load()
        }
    ]

    function num(v) {
        if (v === undefined || v === null || v === "") return "--"
        return Number(v).toFixed(2)
    }

    function load() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText.length > 2) {
                try { root.dataObj = JSON.parse(xhr.responseText) }
                catch (e) { console.log("[wb-usage] 解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/wb-usage.json?t=" + Date.now(), true)
        xhr.send()
        root.online = bridge.wbOnline()
    }

    Timer {
        interval: Math.max(3, root.cfg_refreshSeconds) * 1000
        running: true
        repeat: true
        onTriggered: root.load()
    }
    Component.onCompleted: root.load()

    Component {
        id: usageUi
        ColumnLayout {
            spacing: 4
            clip: true
            Layout.preferredWidth: 236
            Layout.preferredHeight: 158
            Layout.minimumWidth: 190
            Layout.minimumHeight: 124

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "workbuddy"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.minimumWidth: Kirigami.Units.iconSizes.medium
                }
                PlasmaComponents.Label {
                    text: "WorkBuddy 积分 / 用量"
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.9 * root.fs)
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                Rectangle {
                    implicitWidth: 8; implicitHeight: 8
                    Layout.preferredWidth: 8; Layout.preferredHeight: 8
                    Layout.minimumWidth: 8
                    radius: 4
                    color: root.online ? "#27ae60" : "#95a5a6"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                PlasmaComponents.Label {
                    text: root.num(root.dataObj.creditSpent)
                    color: root.brand
                    font.bold: true
                    font.pixelSize: Math.round(26 * root.fs)
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                PlasmaComponents.Label {
                    text: "累计积分"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.72 * root.fs)
                    opacity: 0.7
                    Layout.minimumWidth: 0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: root.dataObj.currentModelName || root.dataObj.currentModel || "当前模型 --"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                PlasmaComponents.Label {
                    text: root.dataObj.modelCredits || ""
                    color: root.brand
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.76 * root.fs)
                    Layout.minimumWidth: 0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 12
                radius: 6
                clip: true
                color: Qt.rgba(0.086, 0.643, 0.290, 0.12)

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, parent.width * (root.dataObj.usagePercent || 0) / 100))
                    height: parent.height
                    radius: 6
                    color: root.brand
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                PlasmaComponents.Label {
                    text: "上下文 " + (root.dataObj.usagePercent || 0) + "%"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.72 * root.fs)
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: (root.dataObj.sessionUsed || 0) + " / " + (root.dataObj.sessionSize || 300000)
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.66 * root.fs)
                    opacity: 0.7
                    Layout.minimumWidth: 0
                }
            }

            PlasmaComponents.Label {
                text: "积分余额由服务端管理，这里显示本地累计消耗与模型倍率。"
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6 * root.fs)
                opacity: 0.55
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }
    }

    compactRepresentation: usageUi
    fullRepresentation: usageUi
}
