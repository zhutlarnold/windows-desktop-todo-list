param(
    [switch]$NoAutostart,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force

$installRoot = Join-Path (Get-GeorgeTodoDataRoot) 'App'
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$startup = [Environment]::GetFolderPath('Startup')

function Copy-InstallFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
        if ($sourceHash -eq $destinationHash) { return }
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    } catch {
        throw "Unable to update $Destination. Exit To-Do List from its tray menu, then run the installer again."
    }
}

if (-not (Test-Path -LiteralPath $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
}

foreach ($fileName in @(
    'GeorgeTodo.ps1',
    'GeorgeTodo.Core.psm1',
    'Launch-GeorgeTodo.cmd',
    'Install-GeorgeTodo.ps1',
    'Install-DesktopShortcut.ps1',
    'Install-Autostart.ps1',
    'README.md'
)) {
    $source = Join-Path $PSScriptRoot $fileName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Installer package is missing: $fileName" }
    Copy-InstallFile -Source $source -Destination (Join-Path $installRoot $fileName)
}

$sourceAssets = Join-Path $PSScriptRoot 'assets'
$targetAssets = Join-Path $installRoot 'assets'
if (-not (Test-Path -LiteralPath $targetAssets)) { New-Item -ItemType Directory -Path $targetAssets -Force | Out-Null }
foreach ($asset in @(Get-ChildItem -LiteralPath $sourceAssets -File)) {
    Copy-InstallFile -Source $asset.FullName -Destination (Join-Path $targetAssets $asset.Name)
}

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
