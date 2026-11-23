import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

KCM.SimpleKCM {
    id: page
    property string cfg_paneLayout
    property bool cfg_showSessionBar
    property bool cfg_showChatPane
    property bool cfg_showThinkPane
    property bool cfg_showAnswerPane
    property bool cfg_showInput
    property bool cfg_showActions
    property double cfg_fontScale
    property int cfg_refreshSeconds

    function initIndex(box, value, isFloat) {
        for (let i = 0; i < box.model.length; i++) {
            const v = box.model[i].v
            if (isFloat ? (Math.abs(v - value) < 0.01) : (v === value)) {
                box.currentIndex = i
                return
            }
        }
    }

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.ComboBox {
            Kirigami.FormData.label: "栏布局:"
            model: [
                { text: "横排三框 (对话 / 思考 / 回答)", v: "horizontal" },
                { text: "上下三框 (竖着堆叠)", v: "stacked" },
                { text: "两框 (对话 / 回答)", v: "two" }
            ]
            textRole: "text"
            Component.onCompleted: page.initIndex(this, page.cfg_paneLayout, false)
            onCurrentIndexChanged: {
                const v = model[currentIndex] ? model[currentIndex].v : "horizontal"
                if (page.cfg_paneLayout !== v) page.cfg_paneLayout = v
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: "显示区块:"
            text: "会话下拉"
            checked: page.cfg_showSessionBar
            onToggled: { if (page.cfg_showSessionBar !== checked) page.cfg_showSessionBar = checked }
        }
        QQC2.CheckBox {
            text: "对话列"
            checked: page.cfg_showChatPane
            onToggled: { if (page.cfg_showChatPane !== checked) page.cfg_showChatPane = checked }
        }
        QQC2.CheckBox {
            text: "思考列 (可折叠)"
            checked: page.cfg_showThinkPane
            onToggled: { if (page.cfg_showThinkPane !== checked) page.cfg_showThinkPane = checked }
        }
        QQC2.CheckBox {
            text: "回答列"
            checked: page.cfg_showAnswerPane
            onToggled: { if (page.cfg_showAnswerPane !== checked) page.cfg_showAnswerPane = checked }
        }
        QQC2.CheckBox {
            text: "底部提问区"
            checked: page.cfg_showInput
            onToggled: { if (page.cfg_showInput !== checked) page.cfg_showInput = checked }
        }
        QQC2.CheckBox {
            text: "底部快捷入口"
            checked: page.cfg_showActions
            onToggled: { if (page.cfg_showActions !== checked) page.cfg_showActions = checked }
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: "字号:"
            model: [
                { text: "小", v: 0.85 },
                { text: "标准", v: 1.0 },
                { text: "大", v: 1.15 }
            ]
            textRole: "text"
            Component.onCompleted: page.initIndex(this, page.cfg_fontScale, true)
            onCurrentIndexChanged: {
                const v = model[currentIndex] ? model[currentIndex].v : 1.0
                if (Math.abs(page.cfg_fontScale - v) >= 0.01) page.cfg_fontScale = v
            }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: "刷新间隔(秒):"
            from: 3; to: 300; stepSize: 1
            value: page.cfg_refreshSeconds
            onValueModified: page.cfg_refreshSeconds = value
        }

        QQC2.Label {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            text: "横排三框/上下三框/两框在此切换；本组件始终是完整对话，不会因拖小而变成积分卡。模型下拉来自 WorkBuddy 本地产品配置。"
            wrapMode: Text.Wrap
            opacity: 0.7
        }
    }
}
