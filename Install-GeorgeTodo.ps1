param(
    [switch]$NoAutostart,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'GeorgeTodo\App'
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$startup = [Environment]::GetFolderPath('Startup')

if (-not (Test-Path -LiteralPath $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
}

foreach ($fileName in @('GeorgeTodo.ps1', 'GeorgeTodo.Core.psm1', 'Launch-GeorgeTodo.cmd', 'README.md')) {
    $source = Join-Path $PSScriptRoot $fileName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Installer package is missing: $fileName" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $installRoot $fileName) -Force
}

$sourceAssets = Join-Path $PSScriptRoot 'assets'
$targetAssets = Join-Path $installRoot 'assets'
if (-not (Test-Path -LiteralPath $targetAssets)) { New-Item -ItemType Directory -Path $targetAssets -Force | Out-Null }
Copy-Item -Path (Join-Path $sourceAssets '*') -Destination $targetAssets -Force

$launcher = Join-Path $installRoot 'Launch-GeorgeTodo.cmd'
$shell = New-Object -ComObject WScript.Shell

$desktopShortcut = $shell.CreateShortcut((Join-Path $desktop 'To-Do List.lnk'))
$desktopShortcut.TargetPath = $launcher
$desktopShortcut.WorkingDirectory = $installRoot
$desktopShortcut.Description = '打开或找回 To-Do List'
$desktopShortcut.Hotkey = 'CTRL+ALT+T'
$desktopShortcut.Save()

if (-not $NoAutostart) {
    $startupShortcut = $shell.CreateShortcut((Join-Path $startup 'To-Do List.lnk'))
    $startupShortcut.TargetPath = $launcher
    $startupShortcut.WorkingDirectory = $installRoot
    $startupShortcut.Description = 'To-Do List - Windows 桌面待办'
    $startupShortcut.Save()
}

Write-Host "Installed to: $installRoot"
Write-Host 'Desktop shortcut created. Press Ctrl + Alt + T to open or recall To-Do List.'
if (-not $NoAutostart) { Write-Host 'Launch at sign-in is enabled.' }

if (-not $NoLaunch) {
    Start-Process -FilePath $launcher -WorkingDirectory $installRoot -WindowStyle Hidden
}
