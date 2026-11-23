import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

KCM.SimpleKCM {
    id: page
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
            text: "小组件只显示余额与用量。如需对话，请在小组件管理器中添加“DSH 对话”。"
            wrapMode: Text.Wrap
            opacity: 0.7
        }
    }
}
