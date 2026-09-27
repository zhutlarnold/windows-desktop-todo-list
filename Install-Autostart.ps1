param([switch]$Remove)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force
$startup = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startup 'To-Do List.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
    $resolvedRoot = Get-GeorgeTodoInstallRoot -ScriptRoot $PSScriptRoot
    $marker = Join-Path $resolvedRoot 'autostart.enabled'
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    Write-Host "Launch at sign-in disabled: $shortcutPath"
    exit 0
}
$installRoot = Get-GeorgeTodoInstallRoot -ScriptRoot $PSScriptRoot
$appRoot = Join-Path $installRoot 'App'
$appScript = Join-Path $appRoot 'GeorgeTodo.ps1'
if (-not (Test-Path -LiteralPath $appScript)) { throw 'Run Install-GeorgeTodo.ps1 before enabling launch at sign-in.' }
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
[IO.File]::WriteAllText((Join-Path $installRoot 'autostart.enabled'), 'enabled', [Text.UTF8Encoding]::new($false))
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellExe
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""
$shortcut.WorkingDirectory = $appRoot
$shortcut.Description = 'To-Do List - Windows 桌面待办'
$shortcut.Save()
Write-Host "Launch at sign-in enabled: $shortcutPath"
