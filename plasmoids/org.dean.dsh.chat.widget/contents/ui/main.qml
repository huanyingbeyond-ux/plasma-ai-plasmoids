import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "org/dean/dsh" as Dsh

// DSH 大态：纯对话栏。三栏内容各自滚动，任何宽度都不溢出。
PlasmoidItem {
    id: root

    property string cfg_paneLayout: Plasmoid.configuration.paneLayout || "horizontal"
    property bool cfg_showSessionBar: Plasmoid.configuration.showSessionBar !== undefined ? Plasmoid.configuration.showSessionBar : true
    property bool cfg_showChatPane: Plasmoid.configuration.showChatPane !== undefined ? Plasmoid.configuration.showChatPane : true
    property bool cfg_showThinkPane: Plasmoid.configuration.showThinkPane !== undefined ? Plasmoid.configuration.showThinkPane : true
    property bool cfg_showAnswerPane: Plasmoid.configuration.showAnswerPane !== undefined ? Plasmoid.configuration.showAnswerPane : true
    property bool cfg_showInput: Plasmoid.configuration.showInput !== undefined ? Plasmoid.configuration.showInput : true
    property double cfg_fontScale: Plasmoid.configuration.fontScale || 1.0
    property int cfg_refreshSeconds: Plasmoid.configuration.refreshSeconds || 8

    readonly property real fs: cfg_fontScale
    readonly property color brand: "#4D6BFE"
    readonly property color paneChat: Qt.rgba(0.302, 0.420, 0.996, 0.13)
    readonly property color paneThink: Qt.rgba(0.302, 0.420, 0.996, 0.05)
    readonly property color paneAnswer: Qt.rgba(0.302, 0.420, 0.996, 0.20)
    // 大态始终是完整对话，不因宽度变小而切换成余额卡；布局只由配置决定
    readonly property bool showChatPane: root.cfg_showChatPane
    readonly property bool showThinkPane: root.cfg_showThinkPane && root.cfg_paneLayout !== "two"
    readonly property bool showAnswerPane: root.cfg_showAnswerPane
    readonly property int visiblePaneCount: (root.showChatPane ? 1 : 0) + (root.showThinkPane ? 1 : 0) + (root.showAnswerPane ? 1 : 0)
    readonly property int paneColumns: root.cfg_paneLayout === "horizontal" ? Math.max(1, root.visiblePaneCount) : 1
    readonly property int paneRows: root.cfg_paneLayout === "horizontal" ? 1 : Math.max(1, root.visiblePaneCount)

    property string title: "DSH 对话"
    property var sessions: []
    readonly property var sessionTitles: {
        const out = []
        for (const s of root.sessions) out.push((s.title || "未命名").slice(0, 20))
        return out
    }
    property var turns: []
    property int activeSession: -1
    property int selectedTurn: -1
    readonly property int activeTurn: (selectedTurn >= 0 && selectedTurn < turns.length) ? selectedTurn : (turns.length - 1)
    readonly property string activeReasoning: (turns.length && activeTurn >= 0) ? (turns[activeTurn].reasoning || "") : ""
    readonly property string activeResponse: (turns.length && activeTurn >= 0) ? (turns[activeTurn].response || "") : ""
    property bool dshOnline: false
    property bool showThinking: true
    property string selectedEffort: "high"

    property var usage: ({})
    readonly property var catalog: (root.usage.catalog || [])
    readonly property var modelNames: {
        const out = []
        for (const m of root.catalog) out.push(m.name || m.id)
        return out.length ? out : ["DeepSeek-V4.1-Flash", "DeepSeek-V4-Pro"]
    }
    property string selectedModel: "deepseek-flash"
    property bool modelTouched: false
    property string statusMessage: ""

    onUsageChanged: {
        if (!root.modelTouched && root.usage.currentModel) root.selectedModel = root.usage.currentModel
    }

    Dsh.DshBridge { id: bridge }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.icon: "dsh-app"
    Plasmoid.title: "DSH 对话"
    toolTipMainText: "DSH 对话"
    toolTipSubText: root.sessions.length ? ("会话：" + root.title) : "桌面直读 DSH 最近问答"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "打开 DSH"
            icon.name: "open-external"
            onTriggered: bridge.openDsh()
        },
        PlasmaCore.Action {
            text: "刷新摘要"
            icon.name: "view-refresh"
            onTriggered: root.loadAll()
        }
    ]

    function notify(msg) {
        root.statusMessage = msg
        statusTimer.restart()
    }

    function selectSession(idx) {
        root.activeSession = idx
        root.selectedTurn = -1
        const list = root.sessions
        if (!list || !list.length) { root.turns = []; root.title = "DSH 对话"; return }
        const i = (idx < 0 || idx >= list.length) ? 0 : idx
        root.turns = list[i].turns || []
        root.title = list[i].title || "DSH 对话"
    }

    function submit() {
        const q = inputField.text.trim()
        if (!q) return
        bridge.submitted.connect(function(ok, msg) {
            root.notify(ok ? "已送入 DSH 输入框，请到 DSH 确认发送" : ("送入失败：" + msg))
        })
        bridge.submit(q, root.selectedEffort + "|" + root.selectedModel)
        inputField.text = ""
    }

    function loadUsage() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText.length > 2) {
                try { root.usage = JSON.parse(xhr.responseText) }
                catch (e) { console.log("[dsh-chat] 用量解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/usage.json?t=" + Date.now(), true)
        xhr.send()
    }

    function loadSummary() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText.length > 2) {
                try {
                    const d = JSON.parse(xhr.responseText)
                    const fresh = d.sessions || []
                    const keep = root.activeSession >= 0 && root.activeSession < fresh.length
                    root.sessions = fresh
                    if (!fresh.length) {
                        root.turns = d.turns || []
                        root.title = d.title || "DSH 对话"
                    } else if (keep) {
                        root.turns = fresh[root.activeSession].turns || []
                        root.title = fresh[root.activeSession].title || "DSH 对话"
                    } else {
                        root.activeSession = -1
                        root.turns = fresh[0].turns || []
                        root.title = fresh[0].title || d.title || "DSH 对话"
                    }
                } catch (e) { console.log("[dsh-chat] 摘要解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/summary.json?t=" + Date.now(), true)
        xhr.send()
        root.dshOnline = bridge.dshOnline()
    }

    function loadAll() {
        root.loadSummary()
        root.loadUsage()
    }

    Timer {
        interval: Math.max(3, root.cfg_refreshSeconds) * 1000
        running: true
        repeat: true
        onTriggered: root.loadAll()
    }
    Timer {
        id: statusTimer
        interval: 4000
        onTriggered: root.statusMessage = ""
    }
    Component.onCompleted: root.loadAll()

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.preferredWidth: 860
        Layout.preferredHeight: 560
        Layout.minimumWidth: 360
        Layout.minimumHeight: 320

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "dsh-app"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            PlasmaComponents.Label {
                text: root.title
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.05 * root.fs)
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Rectangle {
                implicitWidth: 8; implicitHeight: 8
                Layout.preferredWidth: 8; Layout.preferredHeight: 8
                radius: 4
                color: root.dshOnline ? "#27ae60" : "#95a5a6"
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                PlasmaComponents.ToolTip { text: "刷新" }
                onClicked: root.loadAll()
            }
            PlasmaComponents.ToolButton {
                icon.name: "open-external"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                PlasmaComponents.ToolTip { text: "打开完整 DSH" }
                onClicked: bridge.openDsh()
            }
        }

        RowLayout {
            visible: root.cfg_showSessionBar
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: "会话 (" + root.sessions.length + ")"
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.8 * root.fs)
            }
            QQC2.ComboBox {
                model: root.sessionTitles
                Layout.fillWidth: true
                Layout.minimumWidth: 80
                currentIndex: root.activeSession < 0 ? 0 : root.activeSession
                onActivated: root.selectSession(index)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.paneColumns
            rows: root.paneRows
            flow: root.paneColumns === 1 ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            Rectangle {
                clip: true
                radius: 6
                color: root.paneChat
                border.width: 1
                border.color: Qt.rgba(0.302, 0.420, 0.996, 0.22)
                visible: root.showChatPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 80

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    PlasmaComponents.Label {
                        text: "对话"
                        font.bold: true
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.85 * root.fs)
                        Layout.fillWidth: true
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: convCol.height
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
                        Column {
                            id: convCol
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: root.turns
                                delegate: Rectangle {
                                    width: convCol.width
                                    height: 40
                                    radius: 4
                                    clip: true
                                    color: (index === root.activeTurn) ? Qt.rgba(0.2, 0.5, 0.9, 0.22) : "transparent"
                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: modelData.prompt || "（无提问）"
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                                        color: Kirigami.Theme.textColor
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.selectedTurn = index
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                clip: true
                radius: 6
                color: root.paneThink
                border.width: 1
                border.color: Qt.rgba(0.302, 0.420, 0.996, 0.16)
                visible: root.showThinkPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 80

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            text: "思考"
                            font.bold: true
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.85 * root.fs)
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.ToolButton {
                            icon.name: root.showThinking ? "arrow-up" : "arrow-down"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            onClicked: root.showThinking = !root.showThinking
                        }
                    }
                    Flickable {
                        visible: root.showThinking
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: thinkText.height + 8
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
                        PlasmaComponents.Label {
                            id: thinkText
                            width: parent.width
                            text: root.activeReasoning || "（本轮无思考过程）"
                            wrapMode: Text.WrapAnywhere
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.76 * root.fs)
                            opacity: 0.85
                        }
                    }
                }
            }

            Rectangle {
                clip: true
                radius: 6
                color: root.paneAnswer
                border.width: 1
                border.color: Qt.rgba(0.302, 0.420, 0.996, 0.30)
                visible: root.showAnswerPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 96

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    PlasmaComponents.Label {
                        text: "回答"
                        font.bold: true
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.85 * root.fs)
                        Layout.fillWidth: true
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: ansText.height + 8
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
                        PlasmaComponents.Label {
                            id: ansText
                            width: parent.width
                            text: root.activeResponse || "（暂无回答）"
                            wrapMode: Text.WrapAnywhere
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.76 * root.fs)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            visible: root.cfg_showInput
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: "强度"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                }
                QQC2.ComboBox {
                    model: ["低", "中", "高"]
                    currentIndex: 2
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    onCurrentIndexChanged: root.selectedEffort = ["low", "medium", "high"][currentIndex]
                }
                PlasmaComponents.Label {
                    text: "模型"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                }
                QQC2.ComboBox {
                    model: root.modelNames
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    currentIndex: {
                        for (let i = 0; i < root.catalog.length; i++)
                            if (root.catalog[i].id === root.selectedModel) return i
                        return 0
                    }
                    onActivated: {
                        const m = root.catalog[index]
                        if (!m) return
                        root.selectedModel = m.id
                        root.modelTouched = true
                        root.notify("已选模型：" + m.name + "（送入时提示 DSH 切换）")
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.TextField {
                    id: inputField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    placeholderText: "输入问题或要 DSH 做的事…"
                    onAccepted: root.submit()
                }
                PlasmaComponents.Button {
                    text: "送入 DSH"
                    icon.name: "arrow-right"
                    onClicked: root.submit()
                    enabled: inputField.text.trim().length > 0
                }
            }
        }

        PlasmaComponents.Label {
            text: root.statusMessage
            Layout.fillWidth: true
            opacity: 0.8
            elide: Text.ElideRight
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.7 * root.fs)
        }
    }
}
