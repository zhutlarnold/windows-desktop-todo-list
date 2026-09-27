Set-StrictMode -Version Latest

$script:Encouragements = @(
    '今天也从一件小事开始，乔治陪你慢慢完成。',
    '先完成最重要的一步，剩下的路会越来越轻。',
    '不必一口气做到完美，稳稳前进就很好。',
    '把大目标拆成小任务，你已经在掌控今天。',
    '专注眼前这一格，勾选会一点点变多。',
    '认真生活的人，连小小进度都值得庆祝。',
    '今天的你只需要比昨天多前进一点点。',
    '先做五分钟，常常就是顺利开始的秘诀。',
    '每一次完成，都是未来的你收到的小礼物。',
    '给自己一点耐心，成长从来不是赶路比赛。',
    '难题可以慢慢拆，今天也一定有解法。',
    '你的节奏很重要，稳稳完成比匆忙更好。',
    '把注意力交给此刻，进步自然会发生。',
    '清单不是压力，是帮你腾出大脑的小助手。',
    '今天值得一个清楚的计划，也值得好好休息。',
    '完成一项就给自己一个小小的肯定。',
    '先抓住最重要的事，今天就已经成功一半。',
    '你的努力正在积累，只是成果有时晚一点出现。',
    '慢一点没关系，只要方向还是向前。',
    '今天的每个勾，都在替明天减轻一点负担。',
    '把担心写进清单，把精力留给行动。',
    '认真做好眼前这一项，就是很棒的专注。',
    '你不需要同时完成所有事，一件一件来。',
    '再小的进度也是进度，别忘了看见它。',
    '给今天留一点蓝天，也留一点粉色好心情。',
    '计划可以调整，前进不必只有一种样子。',
    '先完成，再优化；先迈步，再寻找完美。',
    '你已经开始整理今天，这本身就是进步。',
    '安静地完成一件难事，会带来很长久的力量。',
    '考试会到来，你的准备也在每天增长。',
    '今天的清单有边界，你的可能性没有。'
)

function Get-DailyEncouragement {
    [CmdletBinding()]
    param([datetime]$Date = (Get-Date))

    $epoch = [datetime]::new(2026, 1, 1)
    $dayNumber = [math]::Floor(($Date.Date - $epoch).TotalDays)
    $index = (($dayNumber % $script:Encouragements.Count) + $script:Encouragements.Count) % $script:Encouragements.Count
    return $script:Encouragements[$index]
}

function Test-SumFutureAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Event,
        [datetime]$Today = (Get-Date)
    )

    $ownerType = [string]$Event.ownerType
    $dateText = [string]$Event.date
    if ($ownerType -ne 'mine' -or [string]::IsNullOrWhiteSpace($dateText)) { return $false }

    $eventDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($dateText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$eventDate)) { return $false }
    if ($eventDate.Date -lt $Today.Date) { return $false }

    $type = [string]$Event.type
    $title = [string]$Event.title
    if ($title -match '(?i)coursework|homework|assignment|project|presentation|report|作业|项目|汇报') { return $false }
    if ($type -in @('考试', '测验')) { return $true }
    return $title -match '(?i)(^|\b)(sum|test|quiz|exam|midterm|final|semester|verbal)(\b|$)|考试|测验|小测|期中|期末'
}

function Read-SumPlanSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到 SUM Plan 共享数据：$Path"
    }
    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Trim()
    $prefix = 'window.SUM_PLAN_SHARED_DATA = '
    if (-not $raw.StartsWith($prefix, [StringComparison]::Ordinal) -or -not $raw.EndsWith(';', [StringComparison]::Ordinal)) {
        throw 'SUM Plan 共享数据格式无法识别。'
    }
    $json = $raw.Substring($prefix.Length, $raw.Length - $prefix.Length - 1)
    $snapshot = $json | ConvertFrom-Json
    if ($snapshot.format -ne 'sum-plan-portable' -or [int]$snapshot.version -ne 2 -or $null -eq $snapshot.events) {
        throw 'SUM Plan 共享快照版本不受支持。'
    }
    return $snapshot
}

function Get-SumFutureExams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [datetime]$Today = (Get-Date)
    )

    return @($Snapshot.events | Where-Object { Test-SumFutureAssessment -Event $_ -Today $Today } | Sort-Object date, time, title)
}

function Get-SumUpcomingItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [datetime]$Today = (Get-Date),
        [ValidateRange(1, 60)][int]$Days = 14
    )

    $start = $Today.Date
    $end = $start.AddDays($Days)
    return @($Snapshot.events | Where-Object {
        if ([string]$_.ownerType -ne 'mine') { return $false }
        $eventDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$_.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$eventDate)) { return $false }
        return $eventDate.Date -ge $start -and $eventDate.Date -le $end
    } | Sort-Object date, time, title)
}

function New-GeorgeTodoState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        version = 1
        groups = @('今日主要事项', '本周计划', '个人事项')
        tasks = @()
        settings = [pscustomobject]@{
            sumDataPath = 'E:\HFI\sum工具\shared-data.js'
            pinned = $true
            draftTask = ''
            draftGroup = '今日主要事项'
        }
    }
}

function Get-GeorgeTodoDataRoot {
    [CmdletBinding()]
    param()

    # Packaged desktop hosts can virtualize LOCALAPPDATA. USERPROFILE remains
    # the canonical Windows profile, so every launcher resolves one data store.
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userProfile)) { $userProfile = $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($userProfile)) { throw '无法确定当前 Windows 用户目录。' }
    return [IO.Path]::GetFullPath((Join-Path $userProfile 'AppData\Local\GeorgeTodo'))
}

function Read-GeorgeTodoState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return New-GeorgeTodoState }
    try {
        return ConvertTo-GeorgeTodoState -Json ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
    } catch {
        $backup = "$Path.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction SilentlyContinue
        $backupFolder = Join-Path (Split-Path -Parent $Path) 'backups'
        if (Test-Path -LiteralPath $backupFolder -PathType Container) {
            foreach ($candidate in @(Get-ChildItem -LiteralPath $backupFolder -Filter 'tasks-*.json' -File | Sort-Object LastWriteTime -Descending)) {
                try {
                    $recovered = ConvertTo-GeorgeTodoState -Json ([IO.File]::ReadAllText($candidate.FullName, [Text.Encoding]::UTF8))
                    Copy-Item -LiteralPath $candidate.FullName -Destination $Path -Force
                    return $recovered
                } catch {}
            }
        }
        return New-GeorgeTodoState
    }
}

function ConvertTo-GeorgeTodoState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) { throw '待办文件为空' }
    $state = $Json | ConvertFrom-Json
    if ([int]$state.version -ne 1 -or $null -eq $state.tasks) { throw '版本不匹配' }
    if ($null -eq $state.groups) { $state | Add-Member -NotePropertyName groups -NotePropertyValue @('今日主要事项') }
    if ($null -eq $state.settings) { $state | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $state.settings.PSObject.Properties['sumDataPath']) { $state.settings | Add-Member -NotePropertyName sumDataPath -NotePropertyValue 'E:\HFI\sum工具\shared-data.js' }
    if (-not $state.settings.PSObject.Properties['pinned']) { $state.settings | Add-Member -NotePropertyName pinned -NotePropertyValue $true }
    if (-not $state.settings.PSObject.Properties['draftTask']) { $state.settings | Add-Member -NotePropertyName draftTask -NotePropertyValue '' }
    if (-not $state.settings.PSObject.Properties['draftGroup']) { $state.settings | Add-Member -NotePropertyName draftGroup -NotePropertyValue '今日主要事项' }
    foreach ($task in @($state.tasks)) {
        if (-not $task.PSObject.Properties['expanded']) { $task | Add-Member -NotePropertyName expanded -NotePropertyValue $true }
        if (-not $task.PSObject.Properties['subtasks'] -or $null -eq $task.subtasks) { $task | Add-Member -Force -NotePropertyName subtasks -NotePropertyValue @() }
    }
    return $state
}

function Save-GeorgeTodoState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Path,
        [switch]$SkipBackup
    )

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    if (-not $SkipBackup -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $backupFolder = Join-Path $folder 'backups'
        if (-not (Test-Path -LiteralPath $backupFolder)) { New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null }
        $backupPath = Join-Path $backupFolder ("tasks-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), [guid]::NewGuid().ToString('N').Substring(0, 8))
        Copy-Item -LiteralPath $Path -Destination $backupPath
        $oldBackups = @(Get-ChildItem -LiteralPath $backupFolder -Filter 'tasks-*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10)
        foreach ($oldBackup in $oldBackups) { Remove-Item -LiteralPath $oldBackup.FullName -Force -ErrorAction SilentlyContinue }
    }
    $temporary = "$Path.tmp"
    $json = $State | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

Export-ModuleMember -Function Get-DailyEncouragement, Test-SumFutureAssessment, Read-SumPlanSnapshot, Get-SumFutureExams, Get-SumUpcomingItems, Get-GeorgeTodoDataRoot, New-GeorgeTodoState, Read-GeorgeTodoState, Save-GeorgeTodoState
