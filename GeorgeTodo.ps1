param([switch]$NoActivate)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms
Import-Module (Join-Path $PSScriptRoot 'GeorgeTodo.Core.psm1') -Force

$script:dataFolder = Join-Path $env:LOCALAPPDATA 'GeorgeTodo'
if (-not (Test-Path -LiteralPath $script:dataFolder)) { New-Item -ItemType Directory -Path $script:dataFolder -Force | Out-Null }
$script:runtimeLog = Join-Path $script:dataFolder 'runtime.log'
function Write-RuntimeLog([string]$Message) {
    try { Add-Content -LiteralPath $script:runtimeLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8 } catch {}
}
trap {
    Write-RuntimeLog "FATAL $($_.Exception.Message)"
    try { [Windows.MessageBox]::Show("To-Do List 启动失败：`n$($_.Exception.Message)`n`n你的待办文件没有被删除。", 'To-Do List', 'OK', 'Error') | Out-Null } catch {}
    break
}

$createdNew = $false
$recallEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\GeorgeTodoRecall')
$mutex = [Threading.Mutex]::new($true, 'Local\GeorgeTodoDesktopApp', [ref]$createdNew)
if (-not $createdNew) {
    try {
        # A previous process may have exited a moment ago while its named mutex is
        # still being released. Taking over that abandoned/released mutex avoids a
        # silent no-window launch during rapid restart or shortcut recall.
        $createdNew = $mutex.WaitOne(1500)
    } catch [Threading.AbandonedMutexException] {
        $createdNew = $true
    }
}
if (-not $createdNew) {
    $recallEvent.Set() | Out-Null
    Write-RuntimeLog 'RECALL signal-sent'
    $mutex.Dispose()
    $recallEvent.Dispose()
    exit 0
}

$script:statePath = Join-Path $script:dataFolder 'tasks.json'
$script:state = Read-GeorgeTodoState -Path $script:statePath
$script:lastSumWrite = [datetime]::MinValue
$script:sumExams = @()
$script:expandedSubtext = [Collections.Generic.HashSet[string]]::new()
$script:allowExit = $false
$script:notifyIcon = $null
Write-RuntimeLog "START version=20260926-anti-loss tasks=$(@($script:state.tasks).Count) source=$PSScriptRoot"

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="To-Do List" Width="410" Height="545" MinWidth="360" MinHeight="460"
        WindowStyle="None" ResizeMode="CanResizeWithGrip" Background="Transparent"
        AllowsTransparency="True" ShowInTaskbar="True" UseLayoutRounding="True">
  <!--
  THESIS: A cheerful pocket planner lives on the desktop edge; it refuses the generic productivity dashboard.
  OWN-WORLD: Powder blue, blush pink, warm paper, navy ink, the user-approved pig mascot crop, and soft offset depth.
  STORY: See today's tasks, unfold their next steps, and glance at the real upcoming SUM subjects without duplicating data.
  FIRST VIEWPORT: A compact bottom-right rail within the user's marked desktop area; mascot and daily note lead, with tasks and linked items scrolling below.
  FORM: Right-edge pocket planner, first-ranked form, seed right-rail-pocket-planner-20260926.
  FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
  -->
  <Window.Resources>
    <SolidColorBrush x:Key="Ink" Color="#12447F"/>
    <SolidColorBrush x:Key="Muted" Color="#6A82A4"/>
    <SolidColorBrush x:Key="Blue" Color="#58A9F1"/>
    <SolidColorBrush x:Key="BlueSoft" Color="#E6F4FF"/>
    <SolidColorBrush x:Key="Pink" Color="#F29ABC"/>
    <SolidColorBrush x:Key="PinkSoft" Color="#FDE7F0"/>
    <SolidColorBrush x:Key="Paper" Color="#FFFFFE"/>
    <Style TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Surface" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="#E6F4FF"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.72"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="#347EBA"/><Setter TargetName="Surface" Property="BorderThickness" Value="2"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#C9DCEE"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="11,8"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="8,5"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Border Background="#FFF9FC" BorderBrush="#F4B2CC" BorderThickness="1.5" CornerRadius="20" ClipToBounds="True">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="44"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Grid.Row="0" Background="#FFF0F6" Padding="12,0">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Image x:Name="HeaderPigImage" Width="42" Height="34" Margin="0,0,6,0" Stretch="Uniform"/>
          <TextBlock Text="To-Do List" FontFamily="Comic Sans MS" FontSize="16" FontWeight="Bold" Foreground="#F34F89" VerticalAlignment="Center"/>
        </StackPanel>
        <Button x:Name="PinButton" Grid.Column="1" ToolTip="保持在最前" Padding="8,5"><TextBlock x:Name="PinLabel" Text="置顶" FontSize="11" Foreground="#F34F89"/></Button>
        <Button x:Name="MinimizeButton" Grid.Column="2" ToolTip="最小化" Width="34"><Path Data="M 3,8 L 15,8" Stroke="#F34F89" StrokeThickness="1.8"/></Button>
        <Button x:Name="CloseButton" Grid.Column="3" ToolTip="关闭" Width="34"><Path Data="M 3,3 L 15,15 M 15,3 L 3,15" Stroke="#F34F89" StrokeThickness="1.8"/></Button>
      </Grid>
    </Border>

    <Border Grid.Row="1" Margin="14,14,14,8" Background="#FDE7F0" CornerRadius="14" Padding="14,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Image x:Name="QuotePigImage" Width="58" Height="48" Margin="0,0,10,0" Stretch="Uniform"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock Text="今天也要稳稳前进" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,3"/>
          <TextBlock x:Name="QuoteText" FontSize="12" Foreground="#6C4A64" TextWrapping="Wrap" LineHeight="19"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="2" Margin="14,4,14,10">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="116"/><ColumnDefinition Width="42"/></Grid.ColumnDefinitions>
      <TextBox x:Name="NewTaskText" Grid.Column="0" ToolTip="输入主事项"/>
      <ComboBox x:Name="GroupCombo" Grid.Column="1" Margin="7,0,0,0" VerticalContentAlignment="Center"/>
      <Button x:Name="AddTaskButton" Grid.Column="2" Margin="6,0,0,0" Background="#F29ABC" ToolTip="添加主事项" Padding="10,7">
        <Path Data="M 8,2 L 8,14 M 2,8 L 14,8" Stroke="White" StrokeThickness="2.2" StrokeStartLineCap="Round"/>
      </Button>
    </Grid>

    <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="14,0,8,0">
      <StackPanel>
        <StackPanel x:Name="TaskHost"/>
        <Grid Margin="0,16,6,8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock Text="未来两周 · SUM 联动" FontSize="17" FontWeight="Bold"/>
            <TextBlock x:Name="ExamSourceLabel" Text="正在读取 SUM Plan…" FontSize="11" Foreground="{StaticResource Muted}" Margin="0,3,0,0"/>
          </StackPanel>
          <Button x:Name="RefreshExamsButton" Grid.Column="1" Content="刷新" FontSize="11" VerticalAlignment="Center"/>
        </Grid>
        <StackPanel x:Name="ExamHost" Margin="0,0,6,18"/>
      </StackPanel>
    </ScrollViewer>

    <Border Grid.Row="4" Background="#E6F4FF" Padding="14,9">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="StatusText" Text="本地保存已开启" FontSize="11" Foreground="#456681" VerticalAlignment="Center"/>
        <Button x:Name="NewGroupButton" Grid.Column="1" Content="新建分组" FontSize="11"/>
      </Grid>
    </Border>
  </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
Write-RuntimeLog 'CHECKPOINT xaml-loaded'
$find = { param([string]$name) $window.FindName($name) }
$taskHost = & $find 'TaskHost'
$examHost = & $find 'ExamHost'
$statusText = & $find 'StatusText'
$groupCombo = & $find 'GroupCombo'
$newTaskText = & $find 'NewTaskText'
$pigPath = Join-Path $PSScriptRoot 'assets\pig-title-logo.png'
if (Test-Path -LiteralPath $pigPath) {
    $pigUri = [uri]::new($pigPath)
    $pigBitmap = [Windows.Media.Imaging.BitmapImage]::new($pigUri)
    (& $find 'HeaderPigImage').Source = $pigBitmap
    (& $find 'QuotePigImage').Source = $pigBitmap
}
Write-RuntimeLog 'CHECKPOINT controls-ready'

function New-Brush([string]$Hex) { return [Windows.Media.BrushConverter]::new().ConvertFromString($Hex) }

function Save-State([string]$Message = '已保存') {
    Save-GeorgeTodoState -State $script:state -Path $script:statePath
    $statusText.Text = $Message
}

function Reload-StateFromDisk {
    try {
        $loadedState = Read-GeorgeTodoState -Path $script:statePath
        if ($null -eq $loadedState -or $null -eq $loadedState.tasks) {
            throw '本地待办文件没有返回有效数据。'
        }
        $script:state = $loadedState
        return $true
    } catch {
        $statusText.Text = '待办读取失败；原文件仍保留，请重试。'
        return $false
    }
}

function Restore-TodoWindow {
    try {
        Write-RuntimeLog "RESTORE begin visible=$($window.IsVisible) state=$($window.WindowState)"
        if (-not $window.IsVisible) { $window.Show() }
        if ($window.WindowState -eq [Windows.WindowState]::Minimized) {
            $window.WindowState = [Windows.WindowState]::Normal
        }
        Dock-Right
        Reload-StateFromDisk | Out-Null
        Refresh-Groups
        Render-Tasks
        $window.Activate() | Out-Null
        $window.Topmost = [bool]$script:state.settings.pinned
        Write-RuntimeLog "RESTORE end visible=$($window.IsVisible) state=$($window.WindowState) tasks=$(@($script:state.tasks).Count)"
    } catch {
        Write-RuntimeLog "RESTORE failed $($_.Exception.Message)"
        throw
    }
}

function Hide-TodoWindow {
    Write-RuntimeLog "HIDE requested visible=$($window.IsVisible)"
    $window.Hide()
    $statusText.Text = '已隐藏；按 Ctrl + Alt + T 可重新打开'
    Write-RuntimeLog "HIDE completed visible=$($window.IsVisible)"
}

function Show-TextEditor {
    param([string]$Title, [string]$Prompt, [string]$Value = '')
    $result = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Value)
    if ([string]::IsNullOrWhiteSpace($result)) { return $null }
    return $result.Trim()
}

function Get-Task([string]$Id) { return $script:state.tasks | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

function New-TextButton([string]$Text, [string]$Tag, [scriptblock]$Handler) {
    $button = [Windows.Controls.Button]::new(); $button.Content=$Text; $button.Tag=$Tag; $button.FontSize=10; $button.Padding='6,3'; $button.Add_Click($Handler); return $button
}

function Render-Tasks {
    $taskHost.Children.Clear()
    foreach($group in @($script:state.groups)) {
        $tasks = @($script:state.tasks | Where-Object { $_.group -eq $group })
        $header = [Windows.Controls.Grid]::new(); $header.Margin='0,8,6,7'
        $header.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $countCol=[Windows.Controls.ColumnDefinition]::new(); $countCol.Width=[Windows.GridLength]::Auto; $header.ColumnDefinitions.Add($countCol)
        $name = [Windows.Controls.TextBlock]::new(); $name.Text=$group; $name.FontFamily='Microsoft YaHei UI'; $name.FontWeight='Bold'; $name.FontSize=17; $header.Children.Add($name) | Out-Null
        $doneCount=@($tasks | Where-Object completed).Count
        $counter=[Windows.Controls.TextBlock]::new(); $counter.Text="$doneCount/$($tasks.Count)"; $counter.FontFamily='Microsoft YaHei UI'; $counter.FontSize=11; $counter.Foreground=New-Brush '#667793'; $counter.VerticalAlignment='Center'; [Windows.Controls.Grid]::SetColumn($counter,1); $header.Children.Add($counter) | Out-Null
        $taskHost.Children.Add($header) | Out-Null
        if(-not $tasks.Count){
            $empty=[Windows.Controls.TextBlock]::new(); $empty.Text='这个分组还没有事项'; $empty.FontFamily='Microsoft YaHei UI'; $empty.FontSize=12; $empty.Foreground=New-Brush '#7B89A0'; $empty.Margin='10,2,0,9'; $taskHost.Children.Add($empty) | Out-Null
            continue
        }
        foreach($task in $tasks){
            $card=[Windows.Controls.Border]::new(); $card.Background=New-Brush '#FFFFFE'; $card.CornerRadius=14; $card.Padding='10,9'; $card.Margin='0,0,6,8'; $card.Effect=[Windows.Media.Effects.DropShadowEffect]@{ Color=[Windows.Media.Color]::FromRgb(98,135,168); BlurRadius=12; ShadowDepth=2; Opacity=.16 }
            $stack=[Windows.Controls.StackPanel]::new()
            $row=[Windows.Controls.Grid]::new();
            $cols=@('*','Auto','Auto','Auto','Auto'); foreach($c in $cols){ $col=[Windows.Controls.ColumnDefinition]::new(); $col.Width=if($c -eq '*'){[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::Auto}; $row.ColumnDefinitions.Add($col) }
            $left=[Windows.Controls.StackPanel]::new(); $left.Orientation='Horizontal'
            $disclosure=[Windows.Controls.Button]::new();$disclosure.Tag=$task.id;$disclosure.Width=22;$disclosure.Height=22;$disclosure.Padding='4';$disclosure.Margin='0,0,3,0';$disclosure.ToolTip=if([bool]$task.expanded){'收起子事项'}else{'展开子事项'};[Windows.Automation.AutomationProperties]::SetName($disclosure,[string]$disclosure.ToolTip)
            $arrow=[Windows.Shapes.Path]::new();$arrow.Stroke=New-Brush '#456681';$arrow.StrokeThickness=1.8;$arrow.StrokeStartLineCap='Round';$arrow.StrokeEndLineCap='Round';$arrow.Data=[Windows.Media.Geometry]::Parse($(if([bool]$task.expanded){'M 2,4 L 7,9 L 12,4'}else{'M 4,2 L 9,7 L 4,12'}));$disclosure.Content=$arrow;$disclosure.Add_Click({param($sender,$args)$target=Get-Task ([string]$sender.Tag);$target.expanded=-not[bool]$target.expanded;Save-State '展开状态已保存';Render-Tasks})
            $check=[Windows.Controls.CheckBox]::new(); $check.IsChecked=[bool]$task.completed; $check.Tag=$task.id; $check.Margin='0,0,7,0'; $mainToggle={ param($sender,$args) $target=Get-Task ([string]$sender.Tag); $target.completed=[bool]$sender.IsChecked; Save-State '主事项状态已保存'; Render-Tasks }; $check.Add_Checked($mainToggle); $check.Add_Unchecked($mainToggle)
            $title=[Windows.Controls.Button]::new(); $title.Tag=$task.id; $title.Padding='2,3'; $title.HorizontalContentAlignment='Left'; $title.Add_Click({ param($sender,$args) $target=Get-Task ([string]$sender.Tag); $target.expanded=-not [bool]$target.expanded; Save-State '展开状态已保存'; Render-Tasks })
            $titleText=[Windows.Controls.TextBlock]::new(); $titleText.Text=$task.title; $titleText.FontFamily='Microsoft YaHei UI'; $titleText.FontSize=13; $titleText.FontWeight='SemiBold'; if($task.completed){ $titleText.TextDecorations=[Windows.TextDecorations]::Strikethrough; $titleText.Opacity=.58 }; $title.Content=$titleText
            $left.Children.Add($disclosure)|Out-Null;$left.Children.Add($check)|Out-Null; $left.Children.Add($title)|Out-Null; $row.Children.Add($left)|Out-Null
            $subtasks=@($task.subtasks); $subDone=@($subtasks|Where-Object completed).Count
            $progress=[Windows.Controls.TextBlock]::new(); $progress.Text="$subDone/$($subtasks.Count)"; $progress.FontFamily='Microsoft YaHei UI'; $progress.FontSize=11; $progress.Foreground=New-Brush '#426B8D'; $progress.Background=New-Brush '#E6F4FF'; $progress.Padding='7,3'; $progress.Margin='4,0'; $progress.VerticalAlignment='Center'; [Windows.Controls.Grid]::SetColumn($progress,1); $row.Children.Add($progress)|Out-Null
            $edit=New-TextButton '编辑' $task.id { param($sender,$args) $target=Get-Task ([string]$sender.Tag); $value=Show-TextEditor '编辑主事项' '主事项名称' ([string]$target.title); if($null-ne$value){$target.title=$value;Save-State '主事项已更新';Render-Tasks} }; [Windows.Controls.Grid]::SetColumn($edit,2); $row.Children.Add($edit)|Out-Null
            $addSub=New-TextButton '加子项' $task.id { param($sender,$args) $target=Get-Task ([string]$sender.Tag); $value=Show-TextEditor '添加子事项' '子事项名称'; if($null-ne$value){$target.subtasks=@($target.subtasks)+[pscustomobject]@{id='sub-'+[guid]::NewGuid().ToString('N');title=$value;completed=$false};$target.expanded=$true;Save-State '子事项已添加';Render-Tasks} }; [Windows.Controls.Grid]::SetColumn($addSub,3); $row.Children.Add($addSub)|Out-Null
            $delete=New-TextButton '删除' $task.id { param($sender,$args) if([Windows.MessageBox]::Show('确定删除这项主事项和全部子事项吗？','确认删除','YesNo','Warning') -eq 'Yes'){ $id=[string]$sender.Tag; $script:state.tasks=@($script:state.tasks|Where-Object{$_.id-ne$id});Save-State '主事项已删除';Render-Tasks } }; $delete.Foreground=New-Brush '#A34C67'; [Windows.Controls.Grid]::SetColumn($delete,4); $row.Children.Add($delete)|Out-Null
            $stack.Children.Add($row)|Out-Null
            if([bool]$task.expanded){
                foreach($sub in $subtasks){
                    $subRow=[Windows.Controls.Grid]::new(); $subRow.Margin='27,6,0,0'; $subRow.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $sc1=[Windows.Controls.ColumnDefinition]::new();$sc1.Width=[Windows.GridLength]::Auto;$subRow.ColumnDefinitions.Add($sc1);$sc2=[Windows.Controls.ColumnDefinition]::new();$sc2.Width=[Windows.GridLength]::Auto;$subRow.ColumnDefinitions.Add($sc2)
                    $subLeft=[Windows.Controls.Grid]::new();$subLeft.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width=[Windows.GridLength]::Auto}));$subLeft.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)}));$subLeft.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width=[Windows.GridLength]::Auto}))
                    $subCheck=[Windows.Controls.CheckBox]::new();$subCheck.IsChecked=[bool]$sub.completed;$subCheck.Tag="$($task.id)|$($sub.id)";$subCheck.Margin='0,0,7,0';$subToggle={param($sender,$args)$parts=([string]$sender.Tag).Split('|');$parent=Get-Task $parts[0];$child=$parent.subtasks|Where-Object{$_.id-eq$parts[1]}|Select-Object -First 1;$child.completed=[bool]$sender.IsChecked;Save-State '子事项状态已保存';Render-Tasks};$subCheck.Add_Checked($subToggle);$subCheck.Add_Unchecked($subToggle)
                    $textKey="$($task.id)|$($sub.id)";$isLong=([string]$sub.title).Length-gt18;$isTextExpanded=$script:expandedSubtext.Contains($textKey)
                    $subText=[Windows.Controls.TextBlock]::new();$subText.Text=$sub.title;$subText.FontFamily='Microsoft YaHei UI';$subText.FontSize=12;$subText.VerticalAlignment='Center';$subText.Margin='0,0,5,0';if($isTextExpanded){$subText.TextWrapping='Wrap'}else{$subText.TextWrapping='NoWrap';$subText.TextTrimming='CharacterEllipsis'};if($sub.completed){$subText.TextDecorations=[Windows.TextDecorations]::Strikethrough;$subText.Opacity=.58}
                    [Windows.Controls.Grid]::SetColumn($subText,1);$subLeft.Children.Add($subCheck)|Out-Null;$subLeft.Children.Add($subText)|Out-Null
                    if($isLong){$more=New-TextButton $(if($isTextExpanded){'收起'}else{'展开全文'}) $textKey {param($sender,$args)$key=[string]$sender.Tag;if($script:expandedSubtext.Contains($key)){$script:expandedSubtext.Remove($key)|Out-Null}else{$script:expandedSubtext.Add($key)|Out-Null};Render-Tasks};$more.Foreground=New-Brush '#F34F89';$more.FontSize=10;[Windows.Controls.Grid]::SetColumn($more,2);$subLeft.Children.Add($more)|Out-Null}
                    $subRow.Children.Add($subLeft)|Out-Null
                    $subEdit=New-TextButton '编辑' "$($task.id)|$($sub.id)" {param($sender,$args)$parts=([string]$sender.Tag).Split('|');$parent=Get-Task $parts[0];$child=$parent.subtasks|Where-Object{$_.id-eq$parts[1]}|Select-Object -First 1;$value=Show-TextEditor '编辑子事项' '子事项名称' ([string]$child.title);if($null-ne$value){$child.title=$value;Save-State '子事项已更新';Render-Tasks}};[Windows.Controls.Grid]::SetColumn($subEdit,1);$subRow.Children.Add($subEdit)|Out-Null
                    $subDelete=New-TextButton '删除' "$($task.id)|$($sub.id)" {param($sender,$args)$parts=([string]$sender.Tag).Split('|');$parent=Get-Task $parts[0];$parent.subtasks=@($parent.subtasks|Where-Object{$_.id-ne$parts[1]});Save-State '子事项已删除';Render-Tasks};$subDelete.Foreground=New-Brush '#A34C67';[Windows.Controls.Grid]::SetColumn($subDelete,2);$subRow.Children.Add($subDelete)|Out-Null
                    $stack.Children.Add($subRow)|Out-Null
                }
                if(-not $subtasks.Count){$hint=[Windows.Controls.TextBlock]::new();$hint.Text='点击“加子项”拆分下一步';$hint.FontFamily='Microsoft YaHei UI';$hint.FontSize=11;$hint.Foreground=New-Brush '#8190A5';$hint.Margin='29,6,0,1';$stack.Children.Add($hint)|Out-Null}
            }
            $card.Child=$stack;$taskHost.Children.Add($card)|Out-Null
        }
    }
}

function Render-Exams {
    $examHost.Children.Clear()
    if(-not $script:sumExams.Count){$empty=[Windows.Controls.TextBlock]::new();$empty.Text='未来两周暂无需要联动的考试或日程。';$empty.FontFamily='Microsoft YaHei UI';$empty.FontSize=12;$empty.Foreground=New-Brush '#7B89A0';$empty.Margin='8,5,0,12';$examHost.Children.Add($empty)|Out-Null;return}
    foreach($exam in @($script:sumExams)){
        $date=[datetime]::ParseExact([string]$exam.date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture);$days=[int]($date.Date-(Get-Date).Date).TotalDays
        $border=[Windows.Controls.Border]::new();$border.Background=New-Brush '#E6F4FF';$border.CornerRadius=12;$border.Padding='11,9';$border.Margin='0,0,0,7'
        $grid=[Windows.Controls.Grid]::new();$grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$auto=[Windows.Controls.ColumnDefinition]::new();$auto.Width=[Windows.GridLength]::Auto;$grid.ColumnDefinitions.Add($auto)
        $copy=[Windows.Controls.StackPanel]::new();$meta=[Windows.Controls.TextBlock]::new();$meta.Text="$($exam.subject) · $($exam.type)";$meta.FontFamily='Microsoft YaHei UI';$meta.FontSize=10;$meta.Foreground=New-Brush '#3B6D94';$name=[Windows.Controls.TextBlock]::new();$name.Text=[string]$exam.title;$name.FontFamily='Microsoft YaHei UI';$name.FontSize=12;$name.FontWeight='SemiBold';$name.TextWrapping='Wrap';$name.Margin='0,2,10,0';$copy.Children.Add($meta)|Out-Null;$copy.Children.Add($name)|Out-Null;$grid.Children.Add($copy)|Out-Null
        $when=[Windows.Controls.StackPanel]::new();$when.HorizontalAlignment='Right';$dateText=[Windows.Controls.TextBlock]::new();$dateText.Text=$date.ToString('MM/dd');$dateText.FontFamily='Microsoft YaHei UI';$dateText.FontWeight='Bold';$dateText.HorizontalAlignment='Right';$count=[Windows.Controls.TextBlock]::new();$count.Text=if($days-eq 0){'今天'}else{"$days 天后"};$count.FontFamily='Microsoft YaHei UI';$count.FontSize=10;$count.Foreground=New-Brush '#667793';$count.HorizontalAlignment='Right';$when.Children.Add($dateText)|Out-Null;$when.Children.Add($count)|Out-Null;[Windows.Controls.Grid]::SetColumn($when,1);$grid.Children.Add($when)|Out-Null
        $border.Child=$grid;$examHost.Children.Add($border)|Out-Null
    }
}

function Refresh-Exams([bool]$Force=$false) {
    $path=[string]$script:state.settings.sumDataPath
    try{
        $write=(Get-Item -LiteralPath $path -ErrorAction Stop).LastWriteTimeUtc
        if($Force -or $write-ne$script:lastSumWrite){
            $snapshot=Read-SumPlanSnapshot -Path $path
            $script:sumExams=@(Get-SumUpcomingItems -Snapshot $snapshot -Days 14)
            $script:lastSumWrite=$write
            (& $find 'ExamSourceLabel').Text="来自 sum工具 · 未来 14 天共 $($script:sumExams.Count) 项 · $(Get-Date -Format 'HH:mm') 更新"
            Render-Exams
        }
    }catch{
        $script:sumExams=@();(& $find 'ExamSourceLabel').Text='未能读取 sum工具；待办功能不受影响';Render-Exams;$statusText.Text=$_.Exception.Message
    }
}

function Refresh-Groups {
    $groupCombo.Items.Clear();foreach($group in @($script:state.groups)){$groupCombo.Items.Add([string]$group)|Out-Null};if($groupCombo.Items.Count){$groupCombo.SelectedIndex=0}
}

function Add-MainTask {
    $value=$newTaskText.Text.Trim();if([string]::IsNullOrWhiteSpace($value)){return}
    $group=if($null-ne$groupCombo.SelectedItem){[string]$groupCombo.SelectedItem}else{'今日主要事项'}
    $script:state.tasks=@($script:state.tasks)+[pscustomobject]@{id='task-'+[guid]::NewGuid().ToString('N');title=$value;group=$group;completed=$false;expanded=$true;subtasks=@()}
    $newTaskText.Clear();Save-State '主事项已添加';Render-Tasks
}

function Dock-Right {
    $physicalArea=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $source=[Windows.PresentationSource]::FromVisual($window)
    $scaleX=if($null-ne$source){$source.CompositionTarget.TransformToDevice.M11}else{1}
    $scaleY=if($null-ne$source){$source.CompositionTarget.TransformToDevice.M22}else{1}
    $areaWidth=$physicalArea.Width/$scaleX
    $areaHeight=$physicalArea.Height/$scaleY
    if($window.ActualHeight-gt$areaHeight-24){$window.Height=$areaHeight-24}
    $window.Left=($physicalArea.Right/$scaleX)-$window.ActualWidth-12
    $window.Top=($physicalArea.Bottom/$scaleY)-$window.ActualHeight-12
}

(& $find 'QuoteText').Text=Get-DailyEncouragement
(& $find 'TitleBar').Add_MouseLeftButtonDown({if($_.ButtonState-eq'Pressed'){$window.DragMove()}})
(& $find 'MinimizeButton').Add_Click({$window.WindowState='Minimized'})
(& $find 'CloseButton').Add_Click({Hide-TodoWindow})
(& $find 'PinButton').Add_Click({$window.Topmost=-not$window.Topmost;$script:state.settings.pinned=$window.Topmost;(& $find 'PinLabel').Text=if($window.Topmost){'置顶'}else{'普通'};Save-State (if($window.Topmost){'已保持在最前'}else{'已取消置顶'})})
(& $find 'AddTaskButton').Add_Click({Add-MainTask})
$newTaskText.Add_KeyDown({if($_.Key-eq'Return'){Add-MainTask}})
(& $find 'RefreshExamsButton').Add_Click({Refresh-Exams $true})
(& $find 'NewGroupButton').Add_Click({$value=Show-TextEditor '新建分组' '分组名称';if($null-ne$value-and$value-notin@($script:state.groups)){$script:state.groups=@($script:state.groups)+$value;Save-State '分组已创建';Refresh-Groups;Render-Tasks;$groupCombo.SelectedItem=$value}})

$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromSeconds(60);$timer.Add_Tick({Refresh-Exams});$timer.Start()
Write-RuntimeLog 'CHECKPOINT timer-started'
$recallTimer=[Windows.Threading.DispatcherTimer]::new();$recallTimer.Interval=[timespan]::FromMilliseconds(250);$recallTimer.Add_Tick({if($recallEvent.WaitOne(0)){Write-RuntimeLog 'RECALL signal-received';Restore-TodoWindow}});$recallTimer.Start()
$trayMenu = [Windows.Forms.ContextMenuStrip]::new()
$showTrayItem = $trayMenu.Items.Add('显示 To-Do List')
$exitTrayItem = $trayMenu.Items.Add('退出')
$script:notifyIcon = [Windows.Forms.NotifyIcon]::new()
$script:notifyIcon.Icon = [Drawing.SystemIcons]::Application
$script:notifyIcon.Text = 'To-Do List'
$script:notifyIcon.ContextMenuStrip = $trayMenu
$script:notifyIcon.Visible = $true
Write-RuntimeLog 'CHECKPOINT tray-ready'
$showTrayItem.Add_Click({Restore-TodoWindow})
$script:notifyIcon.Add_DoubleClick({Restore-TodoWindow})
$exitTrayItem.Add_Click({$script:allowExit=$true;$window.Close()})
$window.Topmost=[bool]$script:state.settings.pinned
$window.Add_Loaded({Write-RuntimeLog 'CHECKPOINT window-loaded-start';Reload-StateFromDisk|Out-Null;Dock-Right;Refresh-Groups;Render-Tasks;Refresh-Exams $true;if(-not$NoActivate){$window.Activate()|Out-Null};Write-RuntimeLog "CHECKPOINT window-loaded-end tasks=$(@($script:state.tasks).Count)"})
$window.Add_LocationChanged({$area=[Windows.SystemParameters]::WorkArea;if([math]::Abs(($window.Left+$window.ActualWidth)-$area.Right)-lt28){$window.Left=$area.Right-$window.ActualWidth-12}})
$window.Add_Closing({param($sender,$args)if(-not$script:allowExit){$args.Cancel=$true;Hide-TodoWindow}})
$window.Add_Closed({$timer.Stop();$recallTimer.Stop();if($null-ne$script:notifyIcon){$script:notifyIcon.Visible=$false;$script:notifyIcon.Dispose()};Write-RuntimeLog 'EXIT';$recallEvent.Dispose();$mutex.ReleaseMutex();$mutex.Dispose()})
Write-RuntimeLog 'CHECKPOINT show-dialog'
$window.ShowDialog() | Out-Null
