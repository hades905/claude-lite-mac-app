# Claude Lite Mac App

一个个人使用的 macOS 桌面聊天客户端，用 SwiftUI 构建。它连接 Tuzi 网关中的 Claude 模型，支持本地会话保存、文件/图片附件选择、Markdown 回复渲染、数学公式渲染，以及发送消息时的“正在回复...”占位提示。

## 功能概览

- 只展示 Claude 模型，并支持恢复上次选择的默认模型。
- 从本地配置文件读取 API key，不使用 macOS Keychain 保存或读取 key。
- 用户发送消息后立即显示“正在回复...”气泡，收到回复后原地替换。
- 用户消息和 AI 回复都使用 Markdown 渲染，支持标题、列表、代码块、加粗、表格和公式。
- 会话记录保存在本机 Application Support 目录，重启后可以恢复。
- 可以选择文件或图片作为附件，并在本地会话中保留附件信息。
- 图片附件发送前会检查大小，超过 20MB 会在本地拒绝，避免内存尖峰和请求过大。
- 提供脚本生成 app 图标并打包为可双击运行的 `.app`。
- 本地日志自动脱敏和轮转，日志总量控制在 100MB 以内。
- 会话记录自动保留最近内容，并限制持久化文本体积，避免长对话无限增大本地数据。
- Markdown 临时渲染文件会自动清理，防止崩溃或强退后留下不断增长的缓存。

## 项目结构

```text
.
├── Package.swift
├── README.md
├── Sources/
│   ├── ClaudeLiteCore/
│   ├── ClaudeLiteMacApp/
│   └── ClaudeLitePackager/
├── scripts/
├── docs/
└── Assets/
```

## 主要目录

`Sources/ClaudeLiteCore`

核心业务代码。这里放模型、服务、会话保存、Markdown HTML 生成、打包器基础能力和主 ViewModel。这个模块不依赖 SwiftUI 视图，方便测试和复用。

`Sources/ClaudeLiteMacApp`

macOS App 入口和界面代码。这里负责窗口、聊天界面、输入框、附件按钮、消息气泡，以及把 Markdown 内容显示到 WebView 中。

`Sources/ClaudeLitePackager`

命令行打包工具入口。`scripts/package-app.sh` 会调用它，把 release 可执行文件、图标和资源 bundle 组装成 `dist/问.app`。

`scripts`

本地辅助脚本。`package-app.sh` 构建 release 版本并封装 `.app`，默认复用 `Assets/AppIcon.icns`；只有图标缺失时才调用 `generate-icon.swift` 重新生成。

`Assets`

长期保留的 app 静态资产，例如固定的 `AppIcon.icns`。

`docs`

接口观察记录和项目说明文档。

## 关键文件说明

`Package.swift`

Swift Package 入口。定义核心库、macOS App 和打包工具。

`Sources/ClaudeLiteCore/ViewModels/ChatViewModel.swift`

聊天界面的状态中心。负责加载本地配置、刷新模型、发送消息、显示 pending 回复、保存会话和处理错误状态。

`Sources/ClaudeLiteCore/Services/TuziAPIClient.swift`

Tuzi 网关 HTTP 客户端。负责请求模型列表和发送 Claude 消息。

`Sources/ClaudeLiteCore/Services/LocalBootstrapConfigurationLoader.swift`

从 `.local/tuzi-config.json` 读取本地配置。这个文件只在本机存在，不应该提交到 GitHub。

`Sources/ClaudeLiteCore/Services/PersistentSessionStore.swift`

把聊天会话保存到本机 Application Support 目录，并在下次启动时恢复。

`Sources/ClaudeLiteCore/Services/RotatingAppLogger.swift`

写入脱敏日志并自动轮转，默认总量上限为 100MB。日志只记录状态、数量、模型和错误类型，不记录完整对话或 API key。

`Sources/ClaudeLiteCore/Services/SessionSnapshotTrimmer.swift`

保存会话前裁剪历史记录，默认保留最近 200 条消息，防止长对话让启动和保存变慢。

`Sources/ClaudeLiteCore/Rendering/MarkdownHTMLDocument.swift`

生成用于渲染 Markdown 的 HTML。内嵌 `marked` 和 MathJax 资源，支持多行文本、标题、加粗、列表、代码块、表格和公式。临时渲染目录会按 100MB 上限自动清理。

`Sources/ClaudeLiteMacApp/MarkdownMessageView.swift`

SwiftUI 和 WKWebView 的桥接层。负责加载 Markdown HTML，并根据内容高度自动调整消息气泡。

`Sources/ClaudeLiteMacApp/MainWindowView.swift`

主窗口界面。包括顶部连接状态、模型选择、消息列表、附件按钮、输入框和发送按钮。

`Sources/ClaudeLiteCore/Packaging/AppBundleBuilder.swift`

封装 `.app` 的核心逻辑。会复制可执行文件、图标和资源 bundle，并写入 `Info.plist`。

## 本地配置

API key 放在项目根目录下的本地文件：

```text
.local/tuzi-config.json
```

示例格式：

```json
{
  "modelAPIKey": "YOUR_MODEL_API_KEY",
  "userAPIKey": "YOUR_USER_API_KEY"
}
```

注意：

- `.local/` 已被 `.gitignore` 忽略。
- 不要把真实 key 提交到 GitHub。
- `./scripts/package-app.sh` 默认不会把 `.local/tuzi-config.json` 打进 `.app`。
- 双击 `Claude Lite Latest.command` 启动时，会把本机配置同步到 `~/Library/Application Support/ClaudeLiteMacApp/.local/tuzi-config.json`，文件权限会设为仅当前用户可读写。
- 当前版本直接读取本地配置文件，不再使用 macOS Keychain。

## 运行

启动开发版 app：

```bash
swift run ClaudeLiteMacApp
```

构建所有 target：

```bash
swift build
```

## 打包

生成可双击运行的 macOS app：

```bash
./scripts/package-app.sh
```

输出位置：

```text
dist/问.app
```

发布前建议压缩 app，并放入 `releases/`：

```bash
mkdir -p releases
ditto -c -k --keepParent dist/问.app releases/问-1.0.1.zip
```

这样可以保留 `.app` 的目录结构和可执行权限。

`releases/` 已被 `.gitignore` 忽略，发布包不提交到源码仓库，避免仓库持续变大。

## 发布注意事项

提交源码前确认不要包含：

- `.local/`
- `.build/`
- `.swiftpm/`
- `.tmp-home/`
- `DerivedData/`
- `.DS_Store`
- 任何 `.env`、`.key`、`.pem`、`.p12` 文件
- 本机 Application Support 中的 `session.json`
- 本机 Application Support 中的 `Logs/`
- `releases/` 中的压缩发布包

发布包只应包含 app 程序、图标和 Markdown/公式渲染资源，不应包含本地 API key 配置文件。

发布前已经运行完整自动化测试，覆盖配置读取、消息发送、Markdown/公式渲染和 app 打包结构。发布压缩包只包含最终 app，不包含测试目录。

## 当前版本

`1.0.1`
