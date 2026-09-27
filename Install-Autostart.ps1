param([switch]$Remove)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'To-Do List.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    Write-Host "Launch at sign-in disabled: $shortcutPath"
    exit 0
}
$installRoot = Join-Path (Get-GeorgeTodoDataRoot) 'App'
$launcher = Join-Path $installRoot 'Launch-GeorgeTodo.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run Install-GeorgeTodo.ps1 before enabling launch at sign-in.' }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'To-Do List - Windows 桌面待办'
$shortcut.Save()
Write-Host "Launch at sign-in enabled: $shortcutPath"
