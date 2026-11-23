import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "org/dean/wb" as Wb

// WorkBuddy 大态：纯对话栏。三栏内容各自滚动，底部快捷入口自动换行。
PlasmoidItem {
    id: root

    property string cfg_paneLayout: Plasmoid.configuration.paneLayout || "horizontal"
    property bool cfg_showSessionBar: Plasmoid.configuration.showSessionBar !== undefined ? Plasmoid.configuration.showSessionBar : true
    property bool cfg_showChatPane: Plasmoid.configuration.showChatPane !== undefined ? Plasmoid.configuration.showChatPane : true
    property bool cfg_showThinkPane: Plasmoid.configuration.showThinkPane !== undefined ? Plasmoid.configuration.showThinkPane : true
    property bool cfg_showAnswerPane: Plasmoid.configuration.showAnswerPane !== undefined ? Plasmoid.configuration.showAnswerPane : true
    property bool cfg_showInput: Plasmoid.configuration.showInput !== undefined ? Plasmoid.configuration.showInput : true
    property bool cfg_showActions: Plasmoid.configuration.showActions !== undefined ? Plasmoid.configuration.showActions : true
    property double cfg_fontScale: Plasmoid.configuration.fontScale || 1.0
    property int cfg_refreshSeconds: Plasmoid.configuration.refreshSeconds || 8

    readonly property real fs: cfg_fontScale
    readonly property color brand: "#16A34A"
    readonly property color paneChat: Qt.rgba(0.086, 0.643, 0.290, 0.13)
    readonly property color paneThink: Qt.rgba(0.086, 0.643, 0.290, 0.05)
    readonly property color paneAnswer: Qt.rgba(0.086, 0.643, 0.290, 0.20)
    // 大态始终是完整对话，布局只由配置决定
    readonly property bool showChatPane: root.cfg_showChatPane
    readonly property bool showThinkPane: root.cfg_showThinkPane && root.cfg_paneLayout !== "two"
    readonly property bool showAnswerPane: root.cfg_showAnswerPane
    readonly property int visiblePaneCount: (root.showChatPane ? 1 : 0) + (root.showThinkPane ? 1 : 0) + (root.showAnswerPane ? 1 : 0)
    readonly property int paneColumns: root.cfg_paneLayout === "horizontal" ? Math.max(1, root.visiblePaneCount) : 1
    readonly property int paneRows: root.cfg_paneLayout === "horizontal" ? 1 : Math.max(1, root.visiblePaneCount)

    property string title: "WorkBuddy"
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
    property bool wbOnline: false
    property bool showThinking: true
    property string statusMessage: ""

    property var usage: ({})
    readonly property var models: (root.usage.models || [])
    readonly property var modelNames: {
        const out = []
        for (const m of root.models) out.push(m.credits ? (m.name + " · " + m.credits) : m.name)
        return out.length ? out : [root.usage.currentModelName || root.usage.currentModel || "Auto"]
    }
    property string selectedModel: "hy4flash-free"
    property bool modelTouched: false

    onUsageChanged: {
        if (!root.modelTouched && root.usage.currentModel) root.selectedModel = root.usage.currentModel
    }

    Wb.WbBridge { id: bridge }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.icon: "workbuddy"
    Plasmoid.title: "WorkBuddy 对话"
    toolTipMainText: "WorkBuddy 对话"
    toolTipSubText: root.sessions.length ? ("会话：" + root.title) : "桌面直读 WorkBuddy 最近对话"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "打开 WorkBuddy"
            icon.name: "open-external"
            onTriggered: bridge.openWorkBuddy()
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
        if (!list || !list.length) { root.turns = []; root.title = "WorkBuddy"; return }
        const i = (idx < 0 || idx >= list.length) ? 0 : idx
        root.turns = list[i].turns || []
        root.title = list[i].title || "WorkBuddy"
    }

    function go(url) {
        bridge.openDeepLink(url)
        bridge.opened.connect(function(ok, msg) {
            root.notify(ok ? ("已唤起：" + url.replace("workbuddy://", "")) : ("失败：" + msg))
        })
    }

    // 提问：只唤起 WorkBuddy 新对话，不写剪贴板（闭源 Electron 无法直接注入输入框）
    function ask() {
        bridge.openDeepLink("workbuddy://chat")
        root.notify(inputField.text.trim() ? "已打开 WorkBuddy，请手动输入问题" : "已打开 WorkBuddy 新对话")
    }

    function selectModel(index) {
        const m = root.models[index]
        if (!m) return
        root.selectedModel = m.id
        root.modelTouched = true
        root.notify("组件已选模型：" + m.name + (m.credits ? "（" + m.credits + "）" : "") + "，请在 WorkBuddy 设置中同步")
    }

    function loadUsage() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText.length > 2) {
                try { root.usage = JSON.parse(xhr.responseText) }
                catch (e) { console.log("[wb-chat] 用量解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/wb-usage.json?t=" + Date.now(), true)
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
                        root.turns = (d.empty || !d.turns) ? [] : d.turns
                        root.title = d.title || "WorkBuddy"
                    } else if (keep) {
                        root.turns = fresh[root.activeSession].turns || []
                        root.title = fresh[root.activeSession].title || "WorkBuddy"
                    } else {
                        root.activeSession = -1
                        root.turns = fresh[0].turns || []
                        root.title = fresh[0].title || d.title || "WorkBuddy"
                    }
                } catch (e) { console.log("[wb-chat] 摘要解析失败: " + e) }
            }
        }
        xhr.open("GET", "file://@USER_HOME@/.local/state/dsh-widget/wb-summary.json?t=" + Date.now(), true)
        xhr.send()
        root.wbOnline = bridge.wbOnline()
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
        interval: 3000
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
                source: "workbuddy"
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
                color: root.wbOnline ? "#27ae60" : "#95a5a6"
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
                PlasmaComponents.ToolTip { text: "打开完整 WorkBuddy" }
                onClicked: bridge.openWorkBuddy()
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
                border.color: Qt.rgba(0.086, 0.643, 0.290, 0.28)
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
                                    height: 36
                                    radius: 4
                                    clip: true
                                    color: (index === root.activeTurn) ? Qt.rgba(0.086, 0.643, 0.290, 0.22) : "transparent"
                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 5
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
                border.color: Qt.rgba(0.086, 0.643, 0.290, 0.18)
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
                border.color: Qt.rgba(0.086, 0.643, 0.290, 0.36)
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
                PlasmaComponents.TextField {
                    id: inputField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    placeholderText: "在此记录问题，点发送打开 WorkBuddy 新对话…"
                    onAccepted: root.ask()
                }
                PlasmaComponents.Button {
                    text: "打开 WorkBuddy"
                    icon.name: "arrow-right"
                    onClicked: root.ask()
                }
            }
        }

        ColumnLayout {
            visible: root.cfg_showActions
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: "模型"
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78 * root.fs)
                }
                QQC2.ComboBox {
                    model: root.modelNames
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    currentIndex: {
                        for (let i = 0; i < root.models.length; i++)
                            if (root.models[i].id === root.selectedModel) return i
                        return 0
                    }
                    onActivated: root.selectModel(index)
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Flow {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Button { text: "新对话"; icon.name: "document-new"; onClicked: root.go("workbuddy://chat") }
                    PlasmaComponents.Button { text: "任务"; icon.name: "view-task"; onClicked: root.go("workbuddy://task") }
                    PlasmaComponents.Button { text: "技能"; icon.name: "quickwizard"; onClicked: root.go("workbuddy://skills") }
                    PlasmaComponents.Button { text: "文件"; icon.name: "document-preview"; onClicked: root.go("workbuddy://my-files") }
                    PlasmaComponents.Button { text: "设置"; icon.name: "configure"; onClicked: root.go("workbuddy://settings") }
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
