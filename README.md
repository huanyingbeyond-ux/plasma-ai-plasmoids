# Plasma AI Plasmoids

> 把 AI 助手变成桌面的一部分 —— 一套 KDE Plasma 原生小组件，用于在同一块桌面上观察 DSH 与 WorkBuddy 的状态、余额/积分、用量与最近对话。

## 灵感来源

这个项目灵感来自 [Omarchy](https://omarchy.org/)（DHH 的 omakase 风格 Linux 发行版）的一句话：

> **"A beautiful system is a motivating system, and productivity has always been downstream from motivation."**

Omarchy 的核心主张是 —— 系统应该开箱即美、观点鲜明（opinionated defaults）、并且把 AI 代理当作桌面上的一等公民（"Your agent should feel at home on your computer"）。

我想要的也是类似的东西：**AI 不该只蜷缩在一个浏览器窗口或一个独立 App 里，它应该像 CPU、内存、天气小组件一样，长在桌面上**。抬眼就能看到额度还剩多少、最近在聊什么，点一下就能把问题送进助手。这就是这个项目想做的"更有原生感的 AI 系统"——不追求花哨的毛玻璃和动画，而是低占用、可移动、能被 KDE 小组件管理器统一管理，跟系统浑然一体。

## 它是什么

四个**互相独立**的 KDE Plasma 小组件（Plasmoid），分属两个应用：

| 组件 ID | 类型 | 显示内容 |
|---|---|---|
| `org.dean.dsh.usage.widget` | 小态 | DSH 余额、累计用量、调用次数、余额曲线 |
| `org.dean.dsh.chat.widget` | 大态 | DSH 会话切换 + 对话/思考/回答三栏 + 思考强度/模型 + 输入直达 DSH |
| `org.dean.workbuddy.usage.widget` | 小态 | WorkBuddy 累计积分、当前模型倍率、上下文用量 |
| `org.dean.workbuddy.chat.widget` | 大态 | WorkBuddy 会话切换 + 三栏 + 真实模型列表 + 新对话/任务/技能/文件/设置入口 |

大小态被刻意做成独立组件，而不是靠组件内部切换：KDE 桌面小组件的外框由 containment 管理，QML 无法可靠地改变自身几何尺寸。分开之后，你可以自由决定摆几个、摆哪里、拖多大。

## 设计原则

- **原生优先**：用真正的 QML Plasmoid，能移动、能关闭、能进 KDE 小组件管理器，右键「布局与外观」可配置。
- **只读为本**：所有数据来自本地只读文件（DSH 会话/账本、WorkBuddy 的本地数据库与缓存），不上传、不联网、不缓存隐私到仓库。
- **真实数据**：模型列表直接解析各自 App 的真实配置（DSH 的模型目录、WorkBuddy 的 58 个模型及 Credits 倍率），不硬编码猜测。
- **低占用**：无动画、无模糊特效；数据刷新默认 8 秒一次，可调。
- **宽度自适应**：大态的对话区支持「横排三框 / 上下三框 / 对话+回答两框」，按可见框数动态布局，窄框自动省略文字不溢出。

## 目录结构

```
plasma-ai-plasmoids/
├── plasmoids/                  # 四个 KDE Plasmoid 包（QML + 配置）
│   ├── org.dean.dsh.usage.widget/
│   ├── org.dean.dsh.chat.widget/
│   ├── org.dean.workbuddy.usage.widget/
│   └── org.dean.workbuddy.chat.widget/
├── bridge/                     # C++ QML 桥接插件源码（gdbus / 深链）
│   ├── dsh-dshbridge.{cpp,h} + dsh-CMakeLists.txt + dsh-Dummy.qml
│   └── wb-wbbridge.{cpp,h}  + wb-CMakeLists.txt  + wb-Dummy.qml
├── helpers/                    # 数据导出脚本 + systemd user service
│   ├── dsh-usage.py            # DSH 余额/用量曲线 + 真实模型目录
│   ├── wb-usage.py             # WorkBuddy 积分/上下文/真实模型
│   ├── wb-summary.py           # WorkBuddy 最近会话摘要
│   └── dsh-summary.service     # 定时刷新服务
├── install.sh                  # 一键：编译插件 → 替换路径 → 安装
└── LICENSE                     # MIT
```

## 依赖

- KDE Plasma 6（Plasmoid API 6.0+）
- Qt 6.5+ 开发包：`Qt6Core` `Qt6Qml`（编译插件用）
- CMake 3.16+、C++17 编译器
- Python 3.10+
- `gdbus`（DSH 桥用）、`xprop`（在线状态检测用）

Debian / Ubuntu:

```bash
sudo apt install cmake g++ qt6-base-dev qt6-declarative-dev python3
```

Arch / EndeavourOS:

```bash
sudo pacman -S cmake gcc qt6-base qt6-declarative python3
```

Fedora / RHEL 系:

```bash
sudo dnf install cmake gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel python3
```

## 安装

```bash
git clone <your-repo-url> plasma-ai-plasmoids
cd plasma-ai-plasmoids
./install.sh
```

`install.sh` 会做四件事：

1. 用 CMake 编译两个 QML 桥接插件（`.so`），装进每个组件的 `contents/ui/org/dean/<dsh|wb>/` 目录；
2. 把所有源码里的 `@USER_HOME@` 占位符替换为当前用户的主目录；
3. 把四个组件包复制到 `~/.local/share/plasma/plasmoids/`；
4. 把 helper 脚本装到 `~/.local/opt/dsh-widget/`、service 装到 `~/.config/systemd/user/`，并刷新缓存。

安装后重启 Plasmashell（或重新登录），在桌面右键「添加小组件」搜索 DSH / WorkBuddy 即可添加。

## 配置

每个组件右键 →「布局与外观」：

- **栏布局**：横排三框 / 上下三框 / 对话+回答两框
- **区块显隐**：会话栏、对话列、思考列、回答列、输入区、快捷入口
- **字号缩放**、**刷新间隔**、**窄态宽度阈值**（仅整合场景）

数值显示来自各自 App 的本地数据；余额/积分的"权威值"在服务端，小组件只展示本地可读的快照与累计值。

## 已知边界

- **WorkBuddy 是闭源 Electron**，无法像 DSH（有 D-Bus 桥）那样把文字直接注入输入框。因此大态的提问框点击后只唤起 WorkBuddy 新对话，问题文字留在输入框供参考，不自动写入剪贴板或输入框。
- **DSH 的"送入"**依赖 `org.dsh.widget` 的 D-Bus 服务与 `~/.local/bin/dsh-native` 启动器；未安装 DSH 时按钮会提示失败，但展示功能不受影响。
- **上网/账号数据不入库**：仓库只含源码，运行时数据写在 `~/.local/state/dsh-widget/`，不会出现在 git 中。

## 致谢

- [Omarchy](https://omarchy.org/) by DHH —— 关于"美观的原生桌面 + AI 一等公民"的灵感。
- KDE Plasma 团队 —— Plasma/Plasmoid 框架。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
