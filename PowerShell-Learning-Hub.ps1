#Requires -Version 5.1
<#
.SYNOPSIS
    Aegis Academy - An interactive PowerShell System Toolkit & Learning Companion
.DESCRIPTION
    A polished, menu-driven console app that is BOTH a real sysadmin toolkit
    AND a self-paced learning tool: it rotates a daily study topic, gives you
    20 hands-on examples per topic, tracks a daily goal, awards XP, and keeps
    a study streak — all persisted locally, no external modules required.
.NOTES
    Run with:  .\PowerShell-Dashboard.ps1
    Progress file: %USERPROFILE%\Documents\AegisAcademy\progress.json
#>

# ============================================================
#  GLOBAL CONFIG
# ============================================================
$Script:AppName      = "AEGIS ACADEMY"
$Script:Version       = "2.0.0"
$Script:LogFile       = Join-Path $env:TEMP "AegisAcademy.log"
$Script:DataDir       = Join-Path $env:USERPROFILE "Documents\AegisAcademy"
$Script:ProgressPath  = Join-Path $Script:DataDir "progress.json"
$Script:AccentColor   = "Cyan"
$Script:OkColor       = "Green"
$Script:WarnColor     = "Yellow"
$Script:BadColor      = "Red"
$Script:GoldColor     = "Magenta"

# ============================================================
#  UTILITY: LOGGING
# ============================================================
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","OK")][string]$Level = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Script:LogFile -Value "[$stamp] [$Level] $Message" -ErrorAction SilentlyContinue
}

# ============================================================
#  UTILITY: UI HELPERS
# ============================================================
function Write-Divider {
    param([string]$Char = "-", [int]$Width = 74, [string]$Color = $Script:AccentColor)
    Write-Host ($Char * $Width) -ForegroundColor $Color
}

function Write-Title {
    param([string]$Text, [string]$Color = $Script:AccentColor)
    Write-Divider -Char "=" -Color $Color
    $pad = [Math]::Max(0, [int](( 74 - $Text.Length ) / 2))
    Write-Host ((" " * $pad) + $Text.ToUpper()) -ForegroundColor $Color
    Write-Divider -Char "=" -Color $Color
}

function Get-ColorForPercent {
    param([double]$Percent)
    if ($Percent -ge 85) { return $Script:BadColor }
    elseif ($Percent -ge 60) { return $Script:WarnColor }
    else { return $Script:OkColor }
}

function Write-MeterBar {
    param([string]$Label, [double]$Percent, [int]$Width = 30, [string]$FillColor = $null)
    $Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $filled = [Math]::Round(($Percent / 100) * $Width)
    $empty  = $Width - $filled
    $color  = if ($FillColor) { $FillColor } else { Get-ColorForPercent -Percent $Percent }
    $bar    = ("#" * $filled) + ("." * $empty)
    Write-Host ("  {0,-18}" -f $Label) -NoNewline -ForegroundColor White
    Write-Host "[$bar] " -NoNewline -ForegroundColor $color
    Write-Host ("{0,5:N1}%" -f $Percent) -ForegroundColor $color
}

function Show-Banner {
    Clear-Host
    $banner = @"
    _    _____ ____ ___ ____      _    ____    _    ____  _____ __  ____   __
   / \  | ____/ ___|_ _/ ___|    / \  / ___|  / \  |  _ \| ____|  \/  \ \ / /
  / _ \ |  _|| |  _ | |\___ \   / _ \| |     / _ \ | | | |  _| | |\/| |\ V /
 / ___ \| |__| |_| || | ___) | / ___ \ |___ / ___ \| |_| | |___| |  | | | |
/_/   \_\_____\____|___|____/ /_/   \_\____/_/   \_\____/|_____|_|  |_| |_|
"@
    Write-Host $banner -ForegroundColor $Script:AccentColor
    Write-Host ("        Sysadmin Toolkit + Daily Learning Companion  -  v$Script:Version") -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================
#  PROGRESS / GAMIFICATION ENGINE
# ============================================================
function Initialize-StudyProgress {
    if (-not (Test-Path $Script:DataDir)) {
        New-Item -ItemType Directory -Path $Script:DataDir -Force | Out-Null
    }
    if (-not (Test-Path $Script:ProgressPath)) {
        $default = [PSCustomObject]@{
            XP              = 0
            Streak          = 0
            BestStreak      = 0
            LastStudyDate   = $null
            DailyGoal       = 10
            TotalCompleted  = 0
            CategoryCounts  = [PSCustomObject]@{}
            History         = @()
        }
        $default | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:ProgressPath -Encoding utf8
        Write-Log -Message "Initialized new progress file." -Level "INFO"
    }
}

function Get-StudyProgress {
    Initialize-StudyProgress
    try {
        return Get-Content -Path $Script:ProgressPath -Raw | ConvertFrom-Json
    } catch {
        Write-Log -Message "Progress file unreadable, recreating." -Level "WARN"
        Remove-Item $Script:ProgressPath -ErrorAction SilentlyContinue
        Initialize-StudyProgress
        return Get-Content -Path $Script:ProgressPath -Raw | ConvertFrom-Json
    }
}

function Save-StudyProgress {
    param([Parameter(Mandatory)]$Progress)
    $Progress | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:ProgressPath -Encoding utf8
}

function Add-CategoryCount {
    param([Parameter(Mandatory)]$Progress, [Parameter(Mandatory)][string]$Key, [int]$Amount)
    if ($Progress.CategoryCounts.PSObject.Properties.Name -contains $Key) {
        $Progress.CategoryCounts.$Key = $Progress.CategoryCounts.$Key + $Amount
    } else {
        $Progress.CategoryCounts | Add-Member -NotePropertyName $Key -NotePropertyValue $Amount
    }
}

function Get-Level     { param([int]$XP) [Math]::Floor($XP / 100) + 1 }
function Get-XpInLevel { param([int]$XP) $XP % 100 }

function Update-StudyStreak {
    param([Parameter(Mandatory)]$Progress)
    $today = (Get-Date).Date
    $last  = if ($Progress.LastStudyDate) { [datetime]$Progress.LastStudyDate } else { $null }

    if ($last -eq $today) {
        # already studied today - streak unchanged
    } elseif ($last -eq $today.AddDays(-1)) {
        $Progress.Streak = [int]$Progress.Streak + 1
    } else {
        $Progress.Streak = 1
    }
    if ([int]$Progress.Streak -gt [int]$Progress.BestStreak) {
        $Progress.BestStreak = $Progress.Streak
    }
    $Progress.LastStudyDate = $today.ToString("yyyy-MM-dd")
}

function Write-MeterBarInline {
    param([double]$Percent, [int]$Width = 20)
    $filled = [Math]::Round(($Percent / 100) * $Width)
    $empty  = $Width - $filled
    Write-Host ("[{0}{1}] " -f ("#" * $filled), ("." * $empty)) -NoNewline -ForegroundColor $Script:GoldColor
}

function Show-StatusBar {
    $p = Get-StudyProgress
    $level = Get-Level -XP $p.XP
    $xpInLevel = Get-XpInLevel -XP $p.XP
    Write-Divider -Char "-"
    Write-Host ("   Lv.{0,-3}" -f $level) -NoNewline -ForegroundColor $Script:GoldColor
    Write-MeterBarInline -Percent $xpInLevel -Width 20
    Write-Host ("  XP {0,-6}  Streak: {1} d (best {2})  Goal: {3}/day" -f $p.XP, $p.Streak, $p.BestStreak, $p.DailyGoal) -ForegroundColor White
    Write-Divider -Char "-"
}

# ============================================================
#  DAILY QUOTES
# ============================================================
$Script:Quotes = @(
    "Small daily practice beats occasional heroics.",
    "Every expert was once a beginner who kept the terminal open.",
    "Automation is a superpower you build one script at a time.",
    "The pipeline doesn't judge you for looking up cmdlet syntax.",
    "Read errors carefully - they are the fastest teacher you have.",
    "Consistency compounds. Twenty minutes a day adds up fast.",
    "You don't need to memorize PowerShell. You need to know how to ask it.",
    "Ship small scripts often; refactor once they prove useful.",
    "A good variable name is worth a thousand comments.",
    "Ctrl+Space is your friend. Let tab-completion do the typing."
)
function Get-QuoteOfTheDay {
    $idx = (Get-Date).DayOfYear % $Script:Quotes.Count
    return $Script:Quotes[$idx]
}

# ============================================================
#  EXAMPLE LIBRARY - 20 hands-on examples per learning topic
# ============================================================
$Script:CategoryMeta = @(
    @{
        Key   = "SystemInfo"
        Title = "System Info"
        Examples = @(
            "View OS name and version quickly :: Get-ComputerInfo | Select-Object WindowsProductName,OsVersion"
            "Query OS details via CIM :: Get-CimInstance Win32_OperatingSystem"
            "Inspect CPU details :: Get-CimInstance Win32_Processor"
            "Read BIOS/firmware info :: Get-CimInstance Win32_BIOS"
            "Read motherboard info :: Get-CimInstance Win32_BaseBoard"
            "List installed RAM modules :: Get-CimInstance Win32_PhysicalMemory"
            "List disk volumes and free space :: Get-Volume"
            "List filesystem drives :: Get-PSDrive -PSProvider FileSystem"
            "Check PowerShell version/edition :: `$PSVersionTable"
            "Check regional/locale settings :: Get-Culture"
            "Check the system time zone :: Get-TimeZone"
            "List installed Windows updates :: Get-HotFix"
            "List running services :: Get-Service | Where-Object Status -eq 'Running'"
            "List network adapters :: Get-NetAdapter"
            "Format the current date/time :: Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"
            "Find last boot time :: (Get-CimInstance Win32_OperatingSystem).LastBootUpTime"
            "List all environment variables :: Get-Item Env:\ | Sort-Object Name"
            "Get the local computer name :: `$env:COMPUTERNAME"
            "Get manufacturer/model/RAM summary :: Get-CimInstance Win32_ComputerSystem"
            "Generate a random number for demos :: Get-Random -Minimum 1 -Maximum 100"
        )
    },
    @{
        Key   = "Processes"
        Title = "Processes"
        Examples = @(
            "List all running processes :: Get-Process"
            "Get a process by name :: Get-Process -Name notepad"
            "Top 5 CPU consumers :: Get-Process | Sort-Object CPU -Descending | Select-Object -First 5"
            "Top 5 memory consumers :: Get-Process | Sort-Object WS -Descending | Select-Object -First 5"
            "Preview stopping a process safely :: Stop-Process -Name notepad -WhatIf"
            "Launch a new process :: Start-Process notepad"
            "Wait until a process exits :: Wait-Process -Name notepad"
            "Filter processes by CPU usage :: Get-Process | Where-Object { `$_.CPU -gt 10 }"
            "Loop through process names :: Get-Process | ForEach-Object { `$_.ProcessName }"
            "Sum total memory used :: Get-Process | Measure-Object -Property WS -Sum"
            "Group processes by publisher :: Get-Process | Group-Object Company"
            "Inspect loaded modules :: Get-Process notepad | Select-Object -ExpandProperty Modules"
            "Custom table output :: Get-Process | Format-Table Name,Id,CPU -AutoSize"
            "Export a process snapshot :: Get-Process | Export-Csv procs.csv -NoTypeInformation"
            "Read a live performance counter :: Get-Counter '\Processor(_Total)\% Processor Time'"
            "Get the current script's own process :: (Get-Process -Id `$PID).ProcessName"
            "Find unresponsive apps :: Get-Process | Where-Object { `$_.Responding -eq `$false }"
            "Show which user owns each process (admin) :: Get-Process -IncludeUserName"
            "Add a calculated property :: Get-Process | Select-Object Name,@{N='MemMB';E={`$_.WS/1MB}}"
            "Sort processes by launch time :: Get-Process | Sort-Object StartTime"
        )
    },
    @{
        Key   = "Network"
        Title = "Network"
        Examples = @(
            "Basic ping test :: Test-Connection -ComputerName 8.8.8.8 -Count 2"
            "Test a specific TCP port :: Test-NetConnection -ComputerName github.com -Port 443"
            "Resolve a hostname to an IP :: Resolve-DnsName github.com"
            "List local IPv4 addresses :: Get-NetIPAddress -AddressFamily IPv4"
            "View full IP configuration :: Get-NetIPConfiguration"
            "List active adapters :: Get-NetAdapter | Where-Object Status -eq 'Up'"
            "View the routing table :: Get-NetRoute -AddressFamily IPv4"
            "List active TCP connections :: Get-NetTCPConnection -State Established"
            "Show configured DNS servers :: Get-DnsClientServerAddress"
            "Fetch a web page :: Invoke-WebRequest -Uri https://example.com"
            "Call a REST API and parse JSON :: Invoke-RestMethod -Uri https://api.github.com"
            "Trace the network path :: Test-NetConnection -ComputerName 8.8.8.8 -TraceRoute"
            "List active firewall rules :: Get-NetFirewallRule | Where-Object Enabled -eq 'True'"
            "Preview a firewall rule :: New-NetFirewallRule -DisplayName 'Test' -Direction Inbound -Action Block -WhatIf"
            "View the ARP/neighbor cache :: Get-NetNeighbor"
            "Ping with a custom delay :: Test-Connection -ComputerName 1.1.1.1 -Count 4 -Delay 2"
            "Extract a field from JSON :: (Invoke-RestMethod -Uri https://api.github.com).current_user_url"
            "Filter addresses by subnet :: Get-NetIPAddress | Where-Object IPAddress -like '192.168.*'"
            "Open a remote SSH session :: ssh user@server"
            "View adapter send/receive stats :: Get-NetAdapterStatistics"
        )
    },
    @{
        Key   = "Files"
        Title = "Files"
        Examples = @(
            "List items in a folder :: Get-ChildItem -Path C:\"
            "Find files recursively by extension :: Get-ChildItem -Recurse -Filter *.log"
            "Check if a path exists :: Test-Path C:\Temp"
            "Create a folder :: New-Item -ItemType Directory -Path C:\Temp\Demo"
            "Copy a file :: Copy-Item file.txt backup.txt"
            "Move a file :: Move-Item file.txt D:\Archive\"
            "Rename a file :: Rename-Item old.txt new.txt"
            "Preview a deletion safely :: Remove-Item temp.txt -WhatIf"
            "Read the last lines of a file :: Get-Content log.txt -Tail 20"
            "Write text to a file :: Set-Content note.txt 'Hello World'"
            "Append text to a file :: Add-Content note.txt 'Another line'"
            "Search inside files like grep :: Select-String -Path *.log -Pattern 'ERROR'"
            "Zip a folder :: Compress-Archive -Path .\Data -DestinationPath data.zip"
            "Unzip an archive :: Expand-Archive -Path data.zip -DestinationPath .\Out"
            "Compute a file checksum :: Get-FileHash file.iso -Algorithm SHA256"
            "View file permissions :: Get-Acl file.txt"
            "Resolve a relative path to full path :: Resolve-Path .\..\"
            "Find the 5 largest files :: Get-ChildItem -Recurse | Sort-Object Length -Descending | Select-Object -First 5"
            "List only folders :: Get-ChildItem -Directory"
            "Load a CSV file as objects :: Get-Content data.csv | ConvertFrom-Csv"
        )
    },
    @{
        Key   = "Hashing"
        Title = "Hashing & Data"
        Examples = @(
            "Compute an MD5 hash :: Get-FileHash file.txt -Algorithm MD5"
            "Create an empty hashtable :: `$h = @{}"
            "Create a hashtable with data :: `$h = @{ Name='Sam'; Age=25 }"
            "Check if a key exists :: `$h.ContainsKey('Name')"
            "Create an order-preserving hashtable :: [ordered]@{ A=1; B=2 }"
            "Group items by a shared property :: Get-ChildItem | Group-Object Extension"
            "Compare two collections for differences :: Compare-Object `$list1 `$list2"
            "Get sum/average/count stats :: Get-ChildItem | Measure-Object -Property Length -Sum -Average"
            "Remove duplicates while sorting :: `$items | Sort-Object -Unique"
            "Remove duplicate objects from a list :: `$items | Select-Object -Unique"
            "Use a strongly-typed list :: `$list = [System.Collections.Generic.List[string]]::new()"
            "Handle an error gracefully :: try { 1/0 } catch { `$_.Exception.Message }"
            "Basic foreach loop :: foreach (`$n in 1..5) { `$n * 2 }"
            "Pipeline-based loop :: 1..5 | ForEach-Object { `$_ * 2 }"
            "Filter using regex :: `$items | Where-Object { `$_.Name -match '^A' }"
            "Filter using wildcard :: `$items | Where-Object { `$_.Name -like 'A*' }"
            "Define a reusable function :: function Get-Square(`$n) { `$n * `$n }"
            "Compare against a size literal :: `$data | Where-Object Size -gt 100MB"
            "Build a structured custom object :: [PSCustomObject]@{ Name='Sam'; Score=90 }"
            "Extract just the hash value :: Get-FileHash file.txt | Select-Object Hash"
        )
    },
    @{
        Key   = "Reporting"
        Title = "Reporting & Output"
        Examples = @(
            "Convert objects into an HTML table :: `$data | ConvertTo-Html -Property Name,Status"
            "Write pipeline output to a file :: Get-Process | Out-File report.txt"
            "Convert objects to JSON :: `$data | ConvertTo-Json -Depth 3"
            "Convert objects to CSV text :: `$data | ConvertTo-Csv -NoTypeInformation"
            "Export objects directly to CSV :: `$data | Export-Csv report.csv -NoTypeInformation"
            "Save objects as native XML :: `$data | Export-Clixml state.xml"
            "Reload previously saved objects :: Import-Clixml state.xml"
            "String interpolation :: `"Hello, `$env:USERNAME!`""
            "Format strings with -f operator :: '{0} is {1} years old' -f 'Sam',25"
            "Build large strings efficiently :: `$sb = [System.Text.StringBuilder]::new()"
            "Join array items into a string :: ('a','b','c') -join ', '"
            "Split a string into an array :: 'a,b,c'.Split(',')"
            "Replace text using regex :: 'Report' -replace 'e','3'"
            "Print verbose diagnostic output :: Write-Verbose 'Debug info' -Verbose"
            "Show a progress bar :: Write-Progress -Activity 'Working' -PercentComplete 50"
            "Multi-branch logic :: switch (3) { 1 {'one'} 2 {'two'} default {'other'} }"
            "Define a function with named params :: function Send-Report { param(`$To,`$Body) }"
            "Open a file with its default app :: Start-Process report.html"
            "Open a folder in File Explorer :: Invoke-Item .\Reports"
            "Get an ISO-8601 timestamp for reports :: Get-Date -Format 'o'"
        )
    }
)
$Script:AllExamplesFlat = $Script:CategoryMeta | ForEach-Object { $_.Examples } | ForEach-Object { $_ }

# ============================================================
#  MODULE 1: SYSTEM HEALTH REPORT
# ============================================================
function Get-SystemHealthReport {
    Write-Title "System Health Report"
    $os    = Get-CimInstance Win32_OperatingSystem
    $cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

    $totalMemGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemGB  = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $memPercent = [Math]::Round((($totalMemGB - $freeMemGB) / $totalMemGB) * 100, 1)

    Write-Host ""
    Write-Host "  Host        : " -NoNewline -ForegroundColor White
    Write-Host $env:COMPUTERNAME -ForegroundColor $Script:AccentColor
    Write-Host "  OS          : " -NoNewline -ForegroundColor White
    Write-Host $os.Caption -ForegroundColor $Script:AccentColor
    Write-Host "  Uptime      : " -NoNewline -ForegroundColor White
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Host ("{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes) -ForegroundColor $Script:AccentColor
    Write-Host "  CPU         : " -NoNewline -ForegroundColor White
    Write-Host $cpu.Name.Trim() -ForegroundColor $Script:AccentColor
    Write-Host ""

    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Write-MeterBar -Label "CPU Load" -Percent $cpuLoad
    Write-MeterBar -Label "Memory Used" -Percent $memPercent
    foreach ($d in $disks) {
        $usedPct = [Math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 1)
        Write-MeterBar -Label "Disk $($d.DeviceID)" -Percent $usedPct
    }

    Write-Host ""
    Write-Log -Message "System health report generated." -Level "OK"
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 2: TOP PROCESSES
# ============================================================
function Get-TopProcesses {
    Write-Title "Top Processes"
    Write-Host ""
    Write-Host "  -- Top by CPU time --" -ForegroundColor $Script:AccentColor
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 8 |
        Format-Table -AutoSize @(
            @{Label="Name"; Expression={$_.ProcessName}},
            @{Label="PID"; Expression={$_.Id}},
            @{Label="CPU(s)"; Expression={[Math]::Round($_.CPU,1)}},
            @{Label="Mem(MB)"; Expression={[Math]::Round($_.WorkingSet64/1MB,1)}}
        ) | Out-Host

    Write-Host "  -- Top by Memory --" -ForegroundColor $Script:AccentColor
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 |
        Format-Table -AutoSize @(
            @{Label="Name"; Expression={$_.ProcessName}},
            @{Label="PID"; Expression={$_.Id}},
            @{Label="Mem(MB)"; Expression={[Math]::Round($_.WorkingSet64/1MB,1)}}
        ) | Out-Host

    Write-Log -Message "Process snapshot taken." -Level "INFO"
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 3: NETWORK DIAGNOSTICS
# ============================================================
function Test-NetworkConnectivity {
    Write-Title "Network Diagnostics"
    Write-Host ""
    foreach ($t in @("8.8.8.8", "1.1.1.1", "github.com", "microsoft.com")) {
        Write-Host -NoNewline ("  Pinging {0,-16}" -f $t) -ForegroundColor White
        $result = Test-Connection -ComputerName $t -Count 2 -ErrorAction SilentlyContinue
        if ($result) {
            $avg = [Math]::Round(($result | Measure-Object -Property ResponseTime -Average).Average, 0)
            Write-Host ("OK  ({0} ms avg)" -f $avg) -ForegroundColor $Script:OkColor
        } else {
            Write-Host "UNREACHABLE" -ForegroundColor $Script:BadColor
        }
    }

    Write-Host ""
    Write-Host "  -- Local IP Configuration --" -ForegroundColor $Script:AccentColor
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" } |
        Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize | Out-Host

    $portTarget = Read-Host "  Enter a host to port-scan (or press Enter to skip)"
    if ($portTarget) {
        foreach ($p in @(21,22,23,25,53,80,110,143,443,3389)) {
            $test = Test-NetConnection -ComputerName $portTarget -Port $p -WarningAction SilentlyContinue
            $status = if ($test.TcpTestSucceeded) { "OPEN" } else { "closed" }
            $color  = if ($test.TcpTestSucceeded) { $Script:OkColor } else { "DarkGray" }
            Write-Host ("    Port {0,-6} {1}" -f $p, $status) -ForegroundColor $color
        }
    }

    Write-Log -Message "Network diagnostics completed." -Level "INFO"
    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 4: LARGE FILE FINDER
# ============================================================
function Find-LargeFiles {
    Write-Title "Large File Finder"
    Write-Host ""
    $path = Read-Host "  Folder to scan (default: $env:USERPROFILE)"
    if (-not $path) { $path = $env:USERPROFILE }
    $minMB = Read-Host "  Minimum size in MB (default: 100)"
    if (-not $minMB) { $minMB = 100 }

    Write-Host "  Scanning $path ..." -ForegroundColor $Script:AccentColor
    $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge ($minMB * 1MB) } |
        Sort-Object Length -Descending | Select-Object -First 20

    if ($files) {
        $files | Format-Table -AutoSize @(
            @{Label="Size(MB)"; Expression={[Math]::Round($_.Length/1MB,1)}},
            @{Label="Name"; Expression={$_.Name}},
            @{Label="Path"; Expression={$_.DirectoryName}}
        ) | Out-Host
    } else {
        Write-Host "  No files found above threshold." -ForegroundColor $Script:WarnColor
    }

    Write-Log -Message "Large file scan on $path (min $minMB MB)." -Level "INFO"
    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 5: DUPLICATE FILE FINDER
# ============================================================
function Find-DuplicateFiles {
    Write-Title "Duplicate File Finder"
    Write-Host ""
    $path = Read-Host "  Folder to scan (default: $env:USERPROFILE\Documents)"
    if (-not $path) { $path = Join-Path $env:USERPROFILE "Documents" }
    if (-not (Test-Path $path)) {
        Write-Host "  Path not found: $path" -ForegroundColor $Script:BadColor
        [void](Read-Host "  Press Enter to return")
        return
    }

    Write-Host "  Hashing files (this may take a moment)..." -ForegroundColor $Script:AccentColor
    $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
    $hashTable = @{}
    $count = 0
    foreach ($f in $files) {
        $count++
        if ($count % 25 -eq 0) { Write-Host -NoNewline "." }
        try {
            $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            if (-not $hashTable.ContainsKey($hash)) { $hashTable[$hash] = @() }
            $hashTable[$hash] += $f.FullName
        } catch { continue }
    }
    Write-Host ""

    $dupes = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
    if ($dupes) {
        $groupNum = 0
        foreach ($d in $dupes) {
            $groupNum++
            Write-Host "  Group $groupNum ($($d.Value.Count) copies):" -ForegroundColor $Script:WarnColor
            $d.Value | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "  No duplicates found." -ForegroundColor $Script:OkColor
    }

    Write-Log -Message "Duplicate scan on $path." -Level "INFO"
    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 6: HTML REPORT EXPORT  (now includes learning stats)
# ============================================================
function Export-HTMLReport {
    Write-Title "Export HTML Report"
    Write-Host ""
    Write-Host "  Gathering data..." -ForegroundColor $Script:AccentColor

    $os      = Get-CimInstance Win32_OperatingSystem
    $cpu     = Get-CimInstance Win32_Processor | Select-Object -First 1
    $disks   = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $memPercent = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    $p        = Get-StudyProgress
    $level    = Get-Level -XP $p.XP
    $xpInLvl  = Get-XpInLevel -XP $p.XP

    $diskRows = ($disks | ForEach-Object {
        $pct = [Math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
        "<tr><td>$($_.DeviceID)</td><td>$pct%</td><td>$([Math]::Round($_.FreeSpace/1GB,1)) GB free</td><td>$([Math]::Round($_.Size/1GB,1)) GB total</td></tr>"
    }) -join "`n"

    $procRows = ($topProcs | ForEach-Object {
        "<tr><td>$($_.ProcessName)</td><td>$($_.Id)</td><td>$([Math]::Round($_.WorkingSet64/1MB,1)) MB</td></tr>"
    }) -join "`n"

    $catRows = ($Script:CategoryMeta | ForEach-Object {
        $c = if ($p.CategoryCounts.PSObject.Properties.Name -contains $_.Key) { $p.CategoryCounts.($_.Key) } else { 0 }
        "<tr><td>$($_.Title)</td><td>$c examples completed</td></tr>"
    }) -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<title>Aegis Academy Report - $env:COMPUTERNAME</title>
<style>
  :root { --accent:#00b7c3; --gold:#c792ea; --bg:#0f1116; --card:#181b22; --text:#e8ecf1; --muted:#8a93a3; }
  * { box-sizing:border-box; }
  body { font-family:'Segoe UI',Consolas,monospace; background:var(--bg); color:var(--text); margin:0; padding:32px; }
  h1 { color:var(--accent); font-size:26px; margin-bottom:4px; }
  .sub { color:var(--muted); margin-bottom:28px; font-size:14px; }
  .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(260px,1fr)); gap:18px; margin-bottom:28px; }
  .card { background:var(--card); border:1px solid #262b36; border-radius:10px; padding:18px 20px; }
  .card h2 { margin:0 0 10px 0; font-size:14px; color:var(--accent); text-transform:uppercase; letter-spacing:0.6px; }
  .card.learn h2 { color:var(--gold); }
  .metric { font-size:30px; font-weight:600; }
  .bar-track { background:#262b36; border-radius:6px; height:10px; margin-top:10px; overflow:hidden; }
  .bar-fill { height:100%; border-radius:6px; background:linear-gradient(90deg,var(--accent),#5eead4); }
  .bar-fill.gold { background:linear-gradient(90deg,var(--gold),#f5a3ff); }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th, td { text-align:left; padding:8px 10px; border-bottom:1px solid #262b36; }
  th { color:var(--muted); font-weight:600; text-transform:uppercase; font-size:11px; }
  footer { margin-top:30px; color:var(--muted); font-size:12px; }
</style>
</head>
<body>
  <h1>Aegis Academy Report</h1>
  <div class='sub'>$env:COMPUTERNAME &bull; $($os.Caption) &bull; Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>

  <div class='grid'>
    <div class='card'><h2>CPU Load</h2><div class='metric'>$cpuLoad%</div>
      <div class='bar-track'><div class='bar-fill' style='width:$cpuLoad%;'></div></div></div>
    <div class='card'><h2>Memory Used</h2><div class='metric'>$memPercent%</div>
      <div class='bar-track'><div class='bar-fill' style='width:$memPercent%;'></div></div></div>
    <div class='card learn'><h2>Learning Level</h2><div class='metric'>Lv. $level</div>
      <div class='bar-track'><div class='bar-fill gold' style='width:$xpInLvl%;'></div></div></div>
    <div class='card learn'><h2>Study Streak</h2><div class='metric'>$($p.Streak) days</div>
      <div style='color:var(--muted); margin-top:6px;'>Best: $($p.BestStreak) days &bull; Total XP: $($p.XP)</div></div>
  </div>

  <div class='card' style='margin-bottom:18px;'>
    <h2>Disk Usage</h2>
    <table><tr><th>Drive</th><th>Used</th><th>Free</th><th>Total</th></tr>$diskRows</table>
  </div>

  <div class='card' style='margin-bottom:18px;'>
    <h2>Top Processes by Memory</h2>
    <table><tr><th>Name</th><th>PID</th><th>Memory</th></tr>$procRows</table>
  </div>

  <div class='card learn'>
    <h2>Study Progress by Topic</h2>
    <table><tr><th>Topic</th><th>Progress</th></tr>$catRows</table>
  </div>

  <footer>Aegis Academy v$Script:Version - auto-generated, no data leaves this machine.</footer>
</body>
</html>
"@

    $outPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "AegisReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html | Out-File -FilePath $outPath -Encoding utf8
    Write-Host "  Report saved to:" -ForegroundColor $Script:OkColor
    Write-Host "  $outPath" -ForegroundColor White
    Write-Log -Message "HTML report exported to $outPath" -Level "OK"

    $open = Read-Host "  Open it now? (Y/N)"
    if ($open -match '^[Yy]') { Start-Process $outPath }

    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 7: DAILY STUDY PLAN  (the learning engine)
# ============================================================
function Show-DailyStudyPlan {
    $progress = Get-StudyProgress
    $today    = Get-Date
    $dow      = [int]$today.DayOfWeek   # Sunday = 0 ... Saturday = 6

    if ($dow -eq 0) {
        $topicTitle = "Mixed Review"
        $examples   = $Script:AllExamplesFlat | Get-Random -Count 20
    } else {
        $meta       = $Script:CategoryMeta[$dow - 1]
        $topicTitle = $meta.Title
        $examples   = $meta.Examples
    }

    Write-Title "Daily Study Plan"
    $hour = $today.Hour
    $greeting = if ($hour -lt 12) { "Good morning" } elseif ($hour -lt 18) { "Good afternoon" } else { "Good evening" }
    Write-Host ""
    Write-Host "  $greeting! Today is $($today.ToString('dddd, MMM d'))." -ForegroundColor White
    Write-Host "  Quote of the day: `"$(Get-QuoteOfTheDay)`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  TODAY'S FOCUS: " -NoNewline -ForegroundColor $Script:GoldColor
    Write-Host $topicTitle -ForegroundColor $Script:GoldColor
    Write-Host ""
    Show-StatusBar
    Write-Host ""

    $i = 0
    foreach ($ex in $examples) {
        $i++
        $parts = $ex -split '::', 2
        $desc = $parts[0].Trim()
        $code = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
        Write-Host ("  {0,2}. " -f $i) -NoNewline -ForegroundColor $Script:AccentColor
        Write-Host $desc -ForegroundColor White
        Write-Host ("      > $code") -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Divider -Char "-"
    $raw = Read-Host "  How many of these 20 did you practice just now? (0-20)"
    $completed = 0
    [void][int]::TryParse($raw, [ref]$completed)
    $completed = [Math]::Max(0, [Math]::Min(20, $completed))

    if ($completed -gt 0) {
        $xpGained = $completed * 5
        $progress.XP = [int]$progress.XP + $xpGained
        $progress.TotalCompleted = [int]$progress.TotalCompleted + $completed
        $catKey = if ($dow -eq 0) { "Review" } else { $Script:CategoryMeta[$dow - 1].Key }
        Add-CategoryCount -Progress $progress -Key $catKey -Amount $completed
        Update-StudyStreak -Progress $progress

        $entry = [PSCustomObject]@{
            Date      = $today.ToString("yyyy-MM-dd")
            Topic     = $topicTitle
            Completed = $completed
            XPGained  = $xpGained
        }
        $progress.History = @($progress.History) + $entry
        Save-StudyProgress -Progress $progress

        Write-Host ""
        Write-Host "  +$xpGained XP earned! Streak: $($progress.Streak) day(s)." -ForegroundColor $Script:OkColor
        if ($completed -ge [int]$progress.DailyGoal) {
            Write-Host "  Daily goal reached! Great work today." -ForegroundColor $Script:GoldColor
        } else {
            $remaining = [int]$progress.DailyGoal - $completed
            Write-Host "  $remaining more example(s) to hit today's goal of $($progress.DailyGoal)." -ForegroundColor $Script:WarnColor
        }
    } else {
        Write-Host ""
        Write-Host "  No worries - come back and log some practice when you're ready." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    [void](Read-Host)
}

# ============================================================
#  MODULE 8: MY GOALS & PROGRESS
# ============================================================
function Show-GoalsAndProgress {
    $progress = Get-StudyProgress
    Write-Title "My Goals & Progress"
    Write-Host ""

    $level    = Get-Level -XP $progress.XP
    $xpInLvl  = Get-XpInLevel -XP $progress.XP

    Write-Host "  Level        : " -NoNewline -ForegroundColor White
    Write-Host $level -ForegroundColor $Script:GoldColor
    Write-MeterBar -Label "XP to next Lv" -Percent $xpInLvl -FillColor $Script:GoldColor
    Write-Host "  Total XP     : " -NoNewline -ForegroundColor White
    Write-Host $progress.XP -ForegroundColor $Script:GoldColor
    Write-Host "  Current Streak: " -NoNewline -ForegroundColor White
    Write-Host "$($progress.Streak) day(s)" -ForegroundColor $Script:OkColor
    Write-Host "  Best Streak  : " -NoNewline -ForegroundColor White
    Write-Host "$($progress.BestStreak) day(s)" -ForegroundColor $Script:OkColor
    Write-Host "  Examples done : " -NoNewline -ForegroundColor White
    Write-Host $progress.TotalCompleted -ForegroundColor $Script:AccentColor
    Write-Host "  Daily Goal   : " -NoNewline -ForegroundColor White
    Write-Host "$($progress.DailyGoal) examples/day" -ForegroundColor $Script:AccentColor

    Write-Host ""
    Write-Host "  -- Progress by Topic --" -ForegroundColor $Script:AccentColor
    foreach ($cat in $Script:CategoryMeta) {
        $c = if ($progress.CategoryCounts.PSObject.Properties.Name -contains $cat.Key) { $progress.CategoryCounts.($cat.Key) } else { 0 }
        Write-MeterBar -Label $cat.Title -Percent ([Math]::Min(100, $c)) -FillColor $Script:AccentColor
    }

    Write-Host ""
    Write-Divider -Char "-"
    Write-Host "  [1] Change daily goal"
    Write-Host "  [2] Reset all progress"
    Write-Host "  [0] Back to menu"
    $choice = Read-Host "  Select an option"

    switch ($choice) {
        "1" {
            $newGoal = Read-Host "  Enter new daily goal (examples per day)"
            $val = 0
            if ([int]::TryParse($newGoal, [ref]$val) -and $val -gt 0) {
                $progress.DailyGoal = $val
                Save-StudyProgress -Progress $progress
                Write-Host "  Daily goal updated to $val." -ForegroundColor $Script:OkColor
            } else {
                Write-Host "  Invalid number, goal unchanged." -ForegroundColor $Script:BadColor
            }
            Start-Sleep -Seconds 1
        }
        "2" {
            $confirm = Read-Host "  Type YES to permanently reset all progress"
            if ($confirm -eq "YES") {
                Remove-Item $Script:ProgressPath -ErrorAction SilentlyContinue
                Initialize-StudyProgress
                Write-Host "  Progress reset." -ForegroundColor $Script:WarnColor
                Start-Sleep -Seconds 1
            }
        }
        default { }
    }
}

# ============================================================
#  MAIN MENU LOOP
# ============================================================
function Show-MainMenu {
    Initialize-StudyProgress
    $menuItems = @(
        @{ Key = "1"; Label = "System Health Report";  Action = { Get-SystemHealthReport } }
        @{ Key = "2"; Label = "Top Processes";          Action = { Get-TopProcesses } }
        @{ Key = "3"; Label = "Network Diagnostics";    Action = { Test-NetworkConnectivity } }
        @{ Key = "4"; Label = "Find Large Files";       Action = { Find-LargeFiles } }
        @{ Key = "5"; Label = "Find Duplicate Files";   Action = { Find-DuplicateFiles } }
        @{ Key = "6"; Label = "Export HTML Report";     Action = { Export-HTMLReport } }
        @{ Key = "7"; Label = "Daily Study Plan";       Action = { Show-DailyStudyPlan } }
        @{ Key = "8"; Label = "My Goals & Progress";    Action = { Show-GoalsAndProgress } }
        @{ Key = "0"; Label = "Exit";                   Action = { $Script:Running = $false } }
    )

    $Script:Running = $true
    while ($Script:Running) {
        Show-Banner
        Show-StatusBar
        Write-Host ""
        foreach ($item in $menuItems) {
            Write-Host ("   [{0}] {1}" -f $item.Key, $item.Label) -ForegroundColor White
        }
        Write-Divider -Char "-"
        Write-Host ("   Log file: {0}" -f $Script:LogFile) -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Select an option"

        $selected = $menuItems | Where-Object { $_.Key -eq $choice }
        if ($selected) {
            Clear-Host
            & $selected.Action
        } else {
            Write-Host "  Invalid selection." -ForegroundColor $Script:BadColor
            Start-Sleep -Seconds 1
        }
    }

    Clear-Host
    Write-Host ""
    Write-Host "  Thanks for studying with $Script:AppName. See you tomorrow!" -ForegroundColor $Script:AccentColor
    Write-Host ""
}

# ============================================================
#  ENTRY POINT
# ============================================================
Write-Log -Message "=== Aegis Academy session started ===" -Level "INFO"
Show-MainMenu
Write-Log -Message "=== Aegis Academy session ended ===" -Level "INFO"
