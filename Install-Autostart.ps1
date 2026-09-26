param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'To-Do List.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    Write-Host "已关闭开机自启：$shortcutPath"
    exit 0
}
$launcher = Join-Path $PSScriptRoot 'Launch-GeorgeTodo.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw "找不到启动文件：$launcher" }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'To-Do List - Windows 桌面待办'
$shortcut.Save()
Write-Host "已开启开机自启：$shortcutPath"
