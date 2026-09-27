param(
    [switch]$NoAutostart,
    [switch]$NoLaunch,
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force

$installRoot = Get-GeorgeTodoInstallRoot -ScriptRoot $PSScriptRoot -PreferredRoot $InstallRoot
$appRoot = Join-Path $installRoot 'App'
$dataRoot = Get-GeorgeTodoDataRoot -InstallRoot $installRoot
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$startup = [Environment]::GetFolderPath('Startup')
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

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

foreach ($folder in @($installRoot, $appRoot, $dataRoot)) {
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
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
    Copy-InstallFile -Source $source -Destination (Join-Path $appRoot $fileName)
}

$sourceAssets = Join-Path $PSScriptRoot 'assets'
$targetAssets = Join-Path $appRoot 'assets'
if (-not (Test-Path -LiteralPath $targetAssets)) { New-Item -ItemType Directory -Path $targetAssets -Force | Out-Null }
foreach ($asset in @(Get-ChildItem -LiteralPath $sourceAssets -File)) {
    Copy-InstallFile -Source $asset.FullName -Destination (Join-Path $targetAssets $asset.Name)
}

[IO.File]::WriteAllText((Join-Path $appRoot 'install-root.txt'), $installRoot, [Text.UTF8Encoding]::new($false))

# Migrate the richest valid legacy state once. Never replace a non-empty state
# with an empty or older copy.
$targetState = Join-Path $dataRoot 'tasks.json'
$legacyCandidates = @()
try {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $profileKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    $profilePath = [Environment]::ExpandEnvironmentVariables([string](Get-ItemPropertyValue -LiteralPath $profileKey -Name ProfileImagePath -ErrorAction Stop))
    $legacyCandidates += Join-Path $profilePath 'AppData\Local\GeorgeTodo\tasks.json'
} catch {}
$legacyCandidates += Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'AppData\Local\GeorgeTodo\tasks.json'
$legacyCandidates += Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GeorgeTodo\tasks.json'

$stateOptions = @()
foreach ($candidate in @($legacyCandidates + $targetState | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    try {
        $candidateState = Read-GeorgeTodoState -Path $candidate
        $subtaskCount = 0
        foreach ($task in @($candidateState.tasks)) { $subtaskCount += @($task.subtasks).Count }
        $stateOptions += [pscustomobject]@{
            Path = $candidate
            Tasks = @($candidateState.tasks).Count
            Subtasks = $subtaskCount
            Modified = (Get-Item -LiteralPath $candidate).LastWriteTimeUtc
        }
    } catch {}
}
$bestState = $stateOptions | Sort-Object Tasks, Subtasks, Modified -Descending | Select-Object -First 1
if ($null -ne $bestState -and $bestState.Path -ne $targetState) {
    $targetTaskCount = 0
    $targetSubtaskCount = 0
    if (Test-Path -LiteralPath $targetState -PathType Leaf) {
        try {
            $targetStateObject = Read-GeorgeTodoState -Path $targetState
            $targetTaskCount = @($targetStateObject.tasks).Count
            foreach ($targetTask in @($targetStateObject.tasks)) { $targetSubtaskCount += @($targetTask.subtasks).Count }
        } catch {}
    }
    $candidateIsRicher = $bestState.Tasks -gt $targetTaskCount -or ($bestState.Tasks -eq $targetTaskCount -and $bestState.Subtasks -gt $targetSubtaskCount)
    if ($candidateIsRicher) {
        if (Test-Path -LiteralPath $targetState -PathType Leaf) {
            $migrationBackups = Join-Path $dataRoot 'backups'
            if (-not (Test-Path -LiteralPath $migrationBackups)) { New-Item -ItemType Directory -Path $migrationBackups -Force | Out-Null }
            $migrationBackupPath = Join-Path $migrationBackups ("tasks-before-migration-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            $targetText = [IO.File]::ReadAllText($targetState, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($migrationBackupPath, $targetText, [Text.UTF8Encoding]::new($false))
        }
        # Content-copy intentionally drops an inherited EFS attribute. The
        # user's E: program drive may not support copying an encrypted file.
        $migratedText = [IO.File]::ReadAllText($bestState.Path, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($targetState, $migratedText, [Text.UTF8Encoding]::new($false))
    }
}

# Ensure a newly migrated installation has an immediately usable recovery
# point even before the user performs the next task edit.
if (Test-Path -LiteralPath $targetState -PathType Leaf) {
    $baselineBackupFolder = Join-Path $dataRoot 'backups'
    if (-not (Test-Path -LiteralPath $baselineBackupFolder)) { New-Item -ItemType Directory -Path $baselineBackupFolder -Force | Out-Null }
    $existingRecoveryPoints = @(Get-ChildItem -LiteralPath $baselineBackupFolder -Filter 'tasks-*.json' -File -ErrorAction SilentlyContinue)
    if ($existingRecoveryPoints.Count -eq 0) {
        $baselinePath = Join-Path $baselineBackupFolder ("tasks-install-baseline-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $baselineText = [IO.File]::ReadAllText($targetState, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($baselinePath, $baselineText, [Text.UTF8Encoding]::new($false))
    }
}

$appScript = Join-Path $appRoot 'GeorgeTodo.ps1'
$shortcutArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""
$shell = New-Object -ComObject WScript.Shell

$desktopShortcut = $shell.CreateShortcut((Join-Path $desktop 'To-Do List.lnk'))
$desktopShortcut.TargetPath = $powershellExe
$desktopShortcut.Arguments = $shortcutArguments
$desktopShortcut.WorkingDirectory = $appRoot
$desktopShortcut.Description = '打开或找回 To-Do List'
$desktopShortcut.Hotkey = 'CTRL+ALT+T'
$desktopShortcut.Save()

if (-not $NoAutostart) {
    [IO.File]::WriteAllText((Join-Path $installRoot 'autostart.enabled'), 'enabled', [Text.UTF8Encoding]::new($false))
    $startupShortcut = $shell.CreateShortcut((Join-Path $startup 'To-Do List.lnk'))
    $startupShortcut.TargetPath = $powershellExe
    $startupShortcut.Arguments = $shortcutArguments
    $startupShortcut.WorkingDirectory = $appRoot
    $startupShortcut.Description = 'To-Do List - Windows 桌面待办'
    $startupShortcut.Save()
}

Write-Host "Installed to: $installRoot"
Write-Host 'Desktop shortcut created. Press Ctrl + Alt + T to open or recall To-Do List.'
if (-not $NoAutostart) { Write-Host 'Launch at sign-in is enabled.' }

if (-not $NoLaunch) {
    Start-Process -FilePath $powershellExe -ArgumentList $shortcutArguments -WorkingDirectory $appRoot -WindowStyle Hidden
}
