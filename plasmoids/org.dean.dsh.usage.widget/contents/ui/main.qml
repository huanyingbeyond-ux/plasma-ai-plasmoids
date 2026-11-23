import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "org/dean/dsh" as Dsh

// DSH 小态：只显示余额 + 用量（含一条轻量余额曲线）
PlasmoidItem {
    id: root

    property double cfg_fontScale: Plasmoid.configuration.fontScale || 1.0
    property int cfg_refreshSeconds: Plasmoid.configuration.refreshSeconds || 8
    readonly property real fs: cfg_fontScale
    readonly property color brand: "#4D6BFE"

    property var usage: ({})
    property bool online: false

    Dsh.DshBridge { id: bridge }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.icon: "dsh-app"
    Plasmoid.title: "DSH 余额用量"
    toolTipMainText: "DSH 余额与用量"
    toolTipSubText: "余额 ¥" + root.money(root.usage.balance) + " · 累计 ¥" + root.money(root.usage.totalCost)

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "打开 DSH"
            icon.name: "open-external"
            onTriggered: bridge.openDsh()
        },
        PlasmaCore.Action {
            text: "刷新"
            icon.name: "view-refresh"
            onTriggered: root.load()
        }
    ]

    function money(v) {
        if (v === undefined || v === null || v === "") return "--"
        return Number(v).toFixed(2)
    }

    function load() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText.length > 2) {
                try { root.usage = JSON.parse(xhr.responseText) }
                catch (e) { console.log("[dsh-usage] 解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/usage.json?t=" + Date.now(), true)
        xhr.send()
        root.online = bridge.dshOnline()
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
            Layout.preferredWidth: 230
            Layout.preferredHeight: 158
            Layout.minimumWidth: 188
            Layout.minimumHeight: 124

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "dsh-app"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.minimumWidth: Kirigami.Units.iconSizes.medium
                }
                PlasmaComponents.Label {
                    text: "DSH 余额 / 用量"
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

            PlasmaComponents.Label {
                text: "¥" + root.money(root.usage.balance)
                color: root.brand
                font.bold: true
                font.pixelSize: Math.round(26 * root.fs)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: "累计 ¥" + root.money(root.usage.totalCost)
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                PlasmaComponents.Label {
                    text: (root.usage.totalCalls || 0) + " 次"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                    opacity: 0.8
                    Layout.minimumWidth: 0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 44
                radius: 6
                clip: true
                color: Qt.rgba(0.302, 0.420, 0.996, 0.08)
                border.width: 1
                border.color: Qt.rgba(0.302, 0.420, 0.996, 0.22)

                Canvas {
                    id: spark
                    anchors.fill: parent
                    anchors.margins: 5
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections { target: root; function onUsageChanged() { spark.requestPaint() } }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const pts = root.usage.days || []
                        if (!pts.length || width < 20 || height < 12) return
                        let vals = []
                        for (const p of pts) vals.push(Number(p.balance) || 0)
                        let lo = Math.min.apply(null, vals)
                        let hi = Math.max.apply(null, vals)
                        if (hi - lo < 0.0001) hi = lo + 1
                        const pad = 3
                        const w = width - pad * 2
                        const h = height - pad * 2
                        const xOf = i => pad + w * (pts.length === 1 ? 0.5 : i / (pts.length - 1))
                        const yOf = v => pad + h * (1 - (v - lo) / (hi - lo))
                        ctx.beginPath()
                        for (let i = 0; i < pts.length; i++) {
                            const x = xOf(i), y = yOf(vals[i])
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                        }
                        ctx.strokeStyle = root.brand
                        ctx.lineWidth = 2
                        ctx.stroke()
                        ctx.lineTo(xOf(pts.length - 1), pad + h)
                        ctx.lineTo(xOf(0), pad + h)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(0.302, 0.420, 0.996, 0.15)
                        ctx.fill()
                    }
                }
            }

            PlasmaComponents.Label {
                text: root.usage.balanceAt ? ("更新 " + root.usage.balanceAt) : "本地余额快照"
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.66 * root.fs)
                opacity: 0.65
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }
    }

    compactRepresentation: usageUi
    fullRepresentation: usageUi
}
