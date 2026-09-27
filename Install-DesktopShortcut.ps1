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
$installRoot = Get-GeorgeTodoInstallRoot -ScriptRoot $PSScriptRoot
$appRoot = Join-Path $installRoot 'App'
$appScript = Join-Path $appRoot 'GeorgeTodo.ps1'
if (-not (Test-Path -LiteralPath $appScript)) { throw 'Run Install-GeorgeTodo.ps1 before creating shortcuts.' }
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellExe
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""
$shortcut.WorkingDirectory = $appRoot
$shortcut.Description = '打开或找回 To-Do List'
$shortcut.Hotkey = 'CTRL+ALT+T'
$shortcut.Save()
Write-Host "Desktop shortcut created: $shortcutPath"
Write-Host 'Press Ctrl+Alt+T to open or recall To-Do List.'
