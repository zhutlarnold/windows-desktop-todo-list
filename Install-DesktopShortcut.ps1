param([switch]$Remove)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$shortcutPath = Join-Path $desktop 'To-Do List.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    Write-Host "Desktop shortcut removed: $shortcutPath"
    exit 0
}
$installRoot = Join-Path (Get-GeorgeTodoDataRoot) 'App'
$launcher = Join-Path $installRoot 'Launch-GeorgeTodo.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run Install-GeorgeTodo.ps1 before creating shortcuts.' }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = '打开或找回 To-Do List'
$shortcut.Hotkey = 'CTRL+ALT+T'
$shortcut.Save()
Write-Host "Desktop shortcut created: $shortcutPath"
Write-Host 'Press Ctrl+Alt+T to open or recall To-Do List.'
