# To-Do List

一个轻量、纯本地的 Windows 桌面 To-Do。窗口默认贴在桌面工作区右侧，支持主事项、可展开子事项、分组、完成进度、每日鼓励语，以及从 SUM Plan 自动读取未来两周的本人考试和日程。

## 功能

- 主事项与子事项的添加、编辑、删除、勾选和折叠。
- 新事项输入框采用写入即保存：尚未按 `+` 的文字也会作为草稿原子保存，重新打开自动恢复。
- 长子事项按需展开，窄窗口中仍能保持操作按钮清晰。
- 本地原子保存、最近 10 份自动备份与损坏自动恢复。
- 鼓励标题和正文每天轮换，31 天内不重样；程序一直留在后台时也会在跨天后自动刷新。
- `×` 隐藏到后台；桌面快捷方式或 `Ctrl + Alt + T` 通过跨沙箱文件信号可靠召回。
- 程序与数据统一放在普通程序盘目录，不再使用 `WpSystem` 或 Codex 隔离区。
- 只读联动 SUM Plan，展示未来 14 天内属于本人的考试和日程。

## 一键安装（推荐）

在项目文件夹中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-GeorgeTodo.ps1
```

在当前电脑上，脚本会安装到 `E:\Programs\To-Do-List`，创建桌面快捷方式、注册 `Ctrl + Alt + T` 并开启当前用户的开机启动。可用 `-InstallRoot` 指定其他普通程序目录；没有 E: 盘时自动回退到当前用户的 `Programs\To-Do-List`。使用 `-NoAutostart` 可以跳过开机启动，使用 `-NoLaunch` 可以只安装而不立即运行。

## 便携启动

双击 `Launch-GeorgeTodo.cmd`。

## 开机自启

右键 `Install-Autostart.ps1`，选择“使用 PowerShell 运行”。它会在当前用户的 Windows 启动文件夹创建快捷方式。关闭自启时运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1 -Remove
```

## 桌面快捷方式与找回窗口

运行 `Install-DesktopShortcut.ps1` 会在桌面创建 `To-Do List` 快捷方式，并注册 `Ctrl+Alt+T`。应用已经运行时，再双击快捷方式或按快捷键不会重复打开，而会恢复并找回原来的窗口。

右上角 `×` 现在只会把窗口隐藏到后台，不会清空或退出待办。程序使用持续的 WPF 应用消息循环，隐藏窗口后后台进程、文件锁和召回监听仍保持运行。除了快捷键和桌面快捷方式，也可以双击系统托盘中的 `To-Do List` 图标重新显示；需要彻底退出时，右键该托盘图标并选择“退出”。

长子事项默认保持单行，避免挤压“编辑 / 删除”操作；文字较长时可点击“展开全文”，阅读后点击“收起”。

## 数据位置

- 稳定安装目录：`E:\Programs\To-Do-List\App`
- To-Do 状态：`E:\Programs\To-Do-List\Data\tasks.json`
- 自动备份：`E:\Programs\To-Do-List\Data\backups`（保留最近 10 份；主文件损坏时自动恢复）
- 运行记录：`E:\Programs\To-Do-List\Data\runtime.log`
- 考试来源：`E:\HFI\sum工具\shared-data.js`

应用只读 SUM Plan 的共享快照，不会复制或写回考试与日程数据。仅显示从今天起 14 天内的本人事项，范围外的内容不会自动放到新 To-Do。SUM Plan 在脚本模式下保存变化时会更新 `shared-data.js`；乔治待办每分钟检查一次变化，也可以点击“刷新”。

桌面和开机快捷方式不再把 `.cmd` 复制件当作目标，而是直接调用 Windows 系统 PowerShell，并把固定程序脚本作为参数。这可防止 Windows 快捷方式跟踪把目标自动改写到 `E:\WpSystem\...\OpenAI.Codex` 副本。程序每次启动还会自检和修正快捷方式。

单实例检测和窗口召回现在使用固定数据目录中的独占文件锁与 `recall.signal`，不再依赖会被 AppContainer 隔离的命名 Mutex/Event。因此即使启动来源不同，也会共享同一份锁、召回信号和 `tasks.json`。

仓库提供了[脱敏运行日志示例](docs/runtime-log-example.txt)。真实日志不会提交到 Git，它只保存在当前电脑的 `E:\Programs\To-Do-List\Data\runtime.log`。GitHub Actions 会在每次推送和 Pull Request 时运行 Windows PowerShell 语法检查及核心测试，可在仓库的 **Actions** 页面查看完整测试日志。

## 设计说明

标题栏直接沿用用户参考图的 “To-Do List” 命名、粉色文字、粉蓝配色与圆润边框。标题小猪 logo 从用户提供的局部参考图中确定性裁切，保存在 `assets\pig-title-logo.png`。窗口针对用户标注的 Windows 桌面右下区域设计，任务操作优先于装饰。
