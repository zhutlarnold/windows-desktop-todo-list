$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\GeorgeTodo.Core.psm1') -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$date = [datetime]'2026-09-26'
Assert-True ((Get-DailyEncouragement -Date $date) -ne (Get-DailyEncouragement -Date $date.AddDays(1))) 'daily encouragement should change on adjacent days'

$fixedInstallRoot = Get-GeorgeTodoInstallRoot -PreferredRoot 'E:\Programs\To-Do-List'
$dataRoot = Get-GeorgeTodoDataRoot -InstallRoot $fixedInstallRoot
Assert-True ($fixedInstallRoot -eq 'E:\Programs\To-Do-List') 'explicit program-drive installation root should be stable'
Assert-True ($dataRoot -eq 'E:\Programs\To-Do-List\Data') 'data should live below the one installation root'
Assert-True ($dataRoot -notmatch '(?i)WpSystem|Packages\\OpenAI\.Codex') 'data root should never use a packaged-app sandbox'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appSource = Get-Content -LiteralPath (Join-Path $projectRoot 'GeorgeTodo.ps1') -Raw
$installerSource = Get-Content -LiteralPath (Join-Path $projectRoot 'Install-GeorgeTodo.ps1') -Raw
Assert-True ($appSource -match 'Get-GeorgeTodoInstallRoot\s+-ScriptRoot\s+\$PSScriptRoot') 'app should resolve its fixed installation marker'
Assert-True ($appSource -match '\$script:dataFolder\s*=\s*Get-GeorgeTodoDataRoot\s+-InstallRoot') 'app should always store data below the fixed installation root'
Assert-True ($appSource -match 'Add_TextChanged\(\{Save-DraftNow\}\)') 'new-task input should be wired to write-through autosave'
Assert-True ($appSource -match '\[IO\.File\]::Open\(\$script:lockPath') 'single instance should use a cross-context exclusive file lock'
Assert-True ($appSource -match 'recall\.signal') 'window recall should use a cross-context file signal'
Assert-True ($appSource -notmatch 'EventWaitHandle|Threading\.Mutex') 'window recall must not rely on app-container kernel namespaces'
Assert-True ($appSource -match '\$script:application\.Run\(\$window\)') 'app should keep a real WPF message loop alive while the window is hidden'
Assert-True ($appSource -notmatch '\$window\.ShowDialog\(\)') 'hiding a modal ShowDialog window would terminate the background process'
Assert-True ($installerSource -match 'Get-GeorgeTodoInstallRoot') 'installer should use the fixed program-drive root helper'
Assert-True ($installerSource -notmatch '\$env:LOCALAPPDATA') 'installer must not trust virtualizable LOCALAPPDATA'
Assert-True ($installerSource -match '\$desktopShortcut\.TargetPath\s*=\s*\$powershellExe') 'desktop shortcut should target system PowerShell, not a trackable copied launcher'
Assert-True ($installerSource -match '\$desktopShortcut\.Arguments\s*=\s*\$shortcutArguments') 'desktop shortcut should carry the canonical app script as an argument'

$exam = [pscustomobject]@{ ownerType = 'mine'; date = '2026-10-02'; type = '考试'; title = 'Physics Final' }
$project = [pscustomobject]@{ ownerType = 'mine'; date = '2026-10-02'; type = '考试'; title = 'Summative Project 1' }
$other = [pscustomobject]@{ ownerType = 'other'; date = '2026-10-02'; type = '考试'; title = 'Math Exam' }
Assert-True (Test-SumFutureAssessment -Event $exam -Today $date) 'future own exam should be included'
Assert-True (-not (Test-SumFutureAssessment -Event $project -Today $date)) 'project should be excluded'
Assert-True (-not (Test-SumFutureAssessment -Event $other -Today $date)) 'other person event should be excluded'

$twoWeekSnapshot = [pscustomobject]@{ events = @(
    [pscustomobject]@{ ownerType = 'mine'; date = '2026-09-26'; type = '考试'; title = 'Today Exam' },
    [pscustomobject]@{ ownerType = 'mine'; date = '2026-10-10'; type = '作业'; title = 'Day 14 Homework' },
    [pscustomobject]@{ ownerType = 'mine'; date = '2026-10-11'; type = '考试'; title = 'Day 15 Exam' },
    [pscustomobject]@{ ownerType = 'other'; date = '2026-09-28'; type = '活动'; title = 'Other Event' }
) }
$linked = @(Get-SumUpcomingItems -Snapshot $twoWeekSnapshot -Today $date -Days 14)
Assert-True ($linked.Count -eq 2) 'linkage should include only own items from today through day 14'
Assert-True ($linked[1].type -eq '作业') 'linkage should include non-exam things inside two weeks'

$tempFolder = Join-Path ([IO.Path]::GetTempPath()) ('GeorgeTodoTests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempFolder | Out-Null
try {
    $markerApp = Join-Path $tempFolder 'MarkerApp'
    New-Item -ItemType Directory -Path $markerApp | Out-Null
    [IO.File]::WriteAllText((Join-Path $markerApp 'install-root.txt'), 'E:\Programs\To-Do-List', [Text.UTF8Encoding]::new($false))
    Assert-True ((Get-GeorgeTodoInstallRoot -ScriptRoot $markerApp) -eq 'E:\Programs\To-Do-List') 'copied app should follow its canonical installation marker'

    $statePath = Join-Path $tempFolder 'tasks.json'
    $state = New-GeorgeTodoState
    Assert-True ($state.settings.draftTask -eq '') 'new state should include an empty autosaved draft'
    Assert-True ($state.settings.draftGroup -eq '今日主要事项') 'new state should include the default draft group'
    $state.tasks = @([pscustomobject]@{ id = 'task-1'; title = '测试主事项'; group = '今日主要事项'; completed = $false; expanded = $true; subtasks = @([pscustomobject]@{ id = 'sub-1'; title = '测试子事项'; completed = $true }) })
    Save-GeorgeTodoState -State $state -Path $statePath
    $loaded = Read-GeorgeTodoState -Path $statePath
    Assert-True ($loaded.tasks.Count -eq 1) 'one task should persist'
    Assert-True ($loaded.tasks[0].subtasks[0].completed) 'subtask completion should persist'

    $state.tasks[0].title = '更新后的事项'
    Save-GeorgeTodoState -State $state -Path $statePath
    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $tempFolder 'backups') -Filter 'tasks-*.json' -File)
    Assert-True ($backupFiles.Count -eq 1) 'saving over an existing state should create a backup'

    $state.settings.draftTask = '尚未按加号的输入也要保存'
    Save-GeorgeTodoState -State $state -Path $statePath -SkipBackup
    $draftLoaded = Read-GeorgeTodoState -Path $statePath
    Assert-True ($draftLoaded.settings.draftTask -eq '尚未按加号的输入也要保存') 'write-through draft should persist immediately'
    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $tempFolder 'backups') -Filter 'tasks-*.json' -File)
    Assert-True ($backupFiles.Count -eq 1) 'draft autosave should not create a backup for every keystroke'

    [IO.File]::WriteAllText($statePath, '{broken json', [Text.UTF8Encoding]::new($false))
    $recovered = Read-GeorgeTodoState -Path $statePath
    Assert-True ($recovered.tasks.Count -eq 1) 'invalid current state should recover a backup'
    Assert-True ($recovered.tasks[0].title -eq '测试主事项') 'recovery should restore the newest valid backup'
    $restored = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($restored.tasks[0].title -eq '测试主事项') 'recovered backup should replace the invalid current state'
} finally {
    Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
}

$sumPath = 'E:\HFI\sum工具\shared-data.js'
if (Test-Path -LiteralPath $sumPath) {
    $snapshot = Read-SumPlanSnapshot -Path $sumPath
    $future = @(Get-SumUpcomingItems -Snapshot $snapshot -Today $date -Days 14)
    Assert-True ($null -ne $snapshot.events) 'real SUM Plan snapshot should parse'
    Write-Host "REAL_SUM_EXAMS=$($future.Count)"
}

Write-Host 'ALL_CORE_TESTS_PASSED'
