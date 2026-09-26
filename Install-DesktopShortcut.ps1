param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$shortcutPath = Join-Path $desktop 'To-Do List.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    Write-Host "已删除桌面快捷方式：$shortcutPath"
    exit 0
}
$launcher = Join-Path $PSScriptRoot 'Launch-GeorgeTodo.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw "找不到启动文件：$launcher" }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = '打开或找回 To-Do List'
$shortcut.Hotkey = 'CTRL+ALT+T'
$shortcut.Save()
Write-Host "已创建桌面快捷方式：$shortcutPath"
Write-Host '也可按 Ctrl+Alt+T 打开或找回 To-Do List。'
