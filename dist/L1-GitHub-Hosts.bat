@echo off
set "SELF=%~f0"
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$p='%SELF%';Get-ChildItem $env:TEMP -Filter 'L1GH_*.ps1' -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime -lt (Get-Date).AddDays(-1)}|Remove-Item -Force -ErrorAction SilentlyContinue;$o=Join-Path $env:TEMP ('L1GH_'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.ps1');$l=@(Get-Content -LiteralPath $p -Encoding UTF8);$i=-1;for($k=0;$k -lt $l.Count;$k++){if($l[$k].Trim() -eq '#PS-START'){$i=$k;break}};if($i -lt 0){exit 2};$l[($i+1)..($l.Count-1)]|Set-Content -LiteralPath $o -Encoding UTF8;& $o"
exit /b
#PS-START
<#
    GitHub 可用 IP 工具 - 图形界面版（仅 Windows）

    做三件事：本机实测各域名的可用 IP、按稳定性排序、一键写入 hosts。
    测速指标是 TTFB（发出请求到收到首个响应字节），不是 ping，也不是 TCP 握手。

    两阶段测速：先单次粗筛，通过的再测两轮确认，整体比逐项测三轮快很多。
#>

param(
    [switch]$SelfTest,
    [switch]$Diagnose,
    [switch]$TestRemote,
    [switch]$NoRemote,
    [switch]$StressTest,
    [switch]$DryRun
)

# ==================== 版本闸门 ====================
# 脚本用到 [ordered]@{}、Get-CimInstance 等 PS 3.0+ 语法。
# Win7 自带 2.0，直接跑会抛一堆语法错误，窗口都不出来 —— 先给一句能看懂的话。
if ($PSVersionTable.PSVersion.Major -lt 3) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            ("本工具需要 PowerShell 3.0 或更高版本。`r`n`r`n当前版本：{0}`r`n`r`nWindows 7 请先安装 WMF 5.1 更新，Windows 8 及以上自带的版本即可。" -f $PSVersionTable.PSVersion),
            'L1 GitHub Hosts', 'OK', 'Error') | Out-Null
    }
    catch { }
    exit 1
}

$ErrorActionPreference = 'Continue'

$IS_GUI = (-not $SelfTest -and -not $TestRemote -and -not $StressTest -and -not $DryRun -and -not $Diagnose)

# ==================== 传输层 ====================
# Windows 7/8 的 .NET 默认只协商到 TLS 1.0，而 GitHub 早已只接受 1.2+。
# 不显式指定的话，旧系统上会出现"所有 IP 都连不上"，而且报错完全看不出原因。
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}
catch { }

# ==================== 崩溃日志 ====================
# 所有未处理异常都落到这一个文件，用户可以直接发回来定位，不用猜。
$LOG_DIR  = Join-Path $env:LOCALAPPDATA 'L1GitHubHosts'
$LOG_FILE = Join-Path $LOG_DIR 'error.log'
$RUN_MARK = Join-Path $LOG_DIR 'running.marker'

function Write-CrashLog {
    param([string]$Scene = '', $Err = $null)
    try {
        if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }
        $b = New-Object System.Text.StringBuilder
        [void]$b.AppendLine(('-' * 60))
        [void]$b.AppendLine('时间   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        [void]$b.AppendLine('场景   : ' + $Scene)
        [void]$b.AppendLine('系统   : ' + [Environment]::OSVersion.VersionString)
        [void]$b.AppendLine('PS     : ' + $PSVersionTable.PSVersion)

        $type = ''; $msg = ''; $stk = ''
        if ($Err) {
            if ($Err -is [System.Management.Automation.ErrorRecord]) {
                $type = $Err.Exception.GetType().FullName
                $msg  = $Err.Exception.Message
                $stk  = $Err.ScriptStackTrace
            }
            elseif ($Err -is [System.Exception]) {
                $type = $Err.GetType().FullName
                $msg  = $Err.Message
                $stk  = $Err.StackTrace
            }
            else { $msg = [string]$Err }
        }
        if ($type) { [void]$b.AppendLine('类型   : ' + $type) }
        [void]$b.AppendLine('信息   : ' + $msg)
        if ($stk) {
            [void]$b.AppendLine('堆栈   :')
            foreach ($ln in (($stk -split "`r?`n") | Select-Object -First 8)) {
                [void]$b.AppendLine('         ' + $ln.Trim())
            }
        }
        [void]$b.AppendLine('')
        [System.IO.File]::AppendAllText($LOG_FILE, $b.ToString(), [System.Text.Encoding]::UTF8)
    }
    catch { }
}

# ==================== 诊断模式 ====================
# 出问题时用这个跑一遍，能看到每一步的实际情况
if ($Diagnose) {
    "PowerShell 版本 : $($PSVersionTable.PSVersion)"
    "系统版本       : $([Environment]::OSVersion.VersionString)"
    "脚本路径       : $PSCommandPath"
    "当前目录       : $(Get-Location)"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    "管理员权限     : $isAdmin"
    ""
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop; "Windows.Forms  : OK" }
    catch { "Windows.Forms  : 失败 - $($_.Exception.Message)" }
    try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop; "System.Drawing  : OK" }
    catch { "System.Drawing  : 失败 - $($_.Exception.Message)" }
    try {
        $t = New-Object System.Windows.Forms.Form
        "窗体创建       : OK ($($t.Width)x$($t.Height))"
        $t.Dispose()
    } catch { "窗体创建       : 失败 - $($_.Exception.Message)" }
    ""
    $hp = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    "hosts 路径     : $hp"
    "hosts 存在     : $(Test-Path $hp)"
    try {
        $null = [System.IO.File]::ReadAllText($hp)
        "hosts 可读     : OK"
    } catch { "hosts 可读     : 失败 - $($_.Exception.Message)" }
    if ($isAdmin) {
        try {
            $bak = $hp + '.writetest'
            Copy-Item $hp $bak -Force -ErrorAction Stop
            Remove-Item $bak -Force -ErrorAction SilentlyContinue
            "hosts 可写     : OK"
        } catch { "hosts 可写     : 失败 - $($_.Exception.Message)" }
    }
    else { "hosts 可写     : 未测（需要管理员）" }
    exit 0
}

# ==================== 自动提权 ====================
# 直接在 %TEMP% 里的原文件上提权运行。因为 bat 不再删除临时文件，
# 提权后的进程一定读得到，不会再出现"文件已被删"导致的闪退。
if (-not $SelfTest -and -not $TestRemote -and -not $StressTest -and -not $DryRun) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $ok = $false
        if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
            try {
                Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") -Verb RunAs -ErrorAction Stop
                $ok = $true
            }
            catch { }
        }
        if ($ok) { exit }

        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "需要管理员权限才能写入 hosts。`r`n`r`n请重新双击运行，并在系统弹窗中点击「是」。`r`n`r`n如果每次都点「是」仍然失败，多半是安全软件拦截，`r`n临时退出 360 或把它加入白名单即可。",
            'L1 GitHub Hosts', 'OK', 'Warning') | Out-Null
        exit
    }
}

# ==================== 单实例 ====================
# 多开是崩溃的放大器：每个实例都会拉起 40 个测速线程，开几个叠加很容易把连接表和内存压穿。
# 第二个实例不再开新窗，直接把已有窗口叫到前台然后退出。
$script:L1Mutex = $null
$script:PrevRun = ''
if ($IS_GUI) {
    try {
        $created = $false
        $script:L1Mutex = New-Object System.Threading.Mutex($true, 'Local\L1GitHubHosts', [ref]$created)
        if (-not $created) {
            try {
                $old = Get-Process -Name powershell -ErrorAction SilentlyContinue |
                       Where-Object { $_.MainWindowTitle -eq 'L1 GitHub Hosts' } |
                       Select-Object -First 1
                if ($old) {
                    # 用 COM 的 AppActivate，省掉一次 Add-Type 编译（那要几百毫秒）
                    $ws = New-Object -ComObject WScript.Shell
                    [void]$ws.AppActivate($old.Id)
                }
            }
            catch { }
            exit 0
        }
    }
    catch { }
}

# 上次是不是没走正常退出：有标记说明进程被结束或崩了，下一轮在日志里说出来
if ($IS_GUI) {
    try {
        if (Test-Path $RUN_MARK) {
            $oldMark = ([System.IO.File]::ReadAllText($RUN_MARK)).Trim()
            if ($oldMark) { $script:PrevRun = $oldMark }
        }
        [System.IO.File]::WriteAllText($RUN_MARK, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    }
    catch { }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==================== 全局异常兜底 ====================
# 没有这一层的话，任何一个没被捕获的异常都会弹 .NET 的"未处理的异常"对话框，
# 用户除了关掉没有别的选择，也拿不到任何信息。现在统一记日志 + 友好提示。
try {
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        Write-CrashLog '界面线程' $e.Exception
        try {
            [System.Windows.Forms.MessageBox]::Show(
                ("程序遇到一个问题，已经记录，其余功能可以继续使用。`r`n`r`n" + $e.Exception.Message + "`r`n`r`n日志：`r`n" + $LOG_FILE),
                'L1 GitHub Hosts', 'OK', 'Warning') | Out-Null
        } catch { }
    })
}
catch { }

try {
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        Write-CrashLog '后台线程' $e.ExceptionObject
    })
}
catch { }

# ==================== 配置 ====================
$TIMEOUT_MS   = 2200
$ATTEMPTS     = 3
$THREADS      = 40

$MARK_START  = '# === GitHub IP BEGIN ==='
$MARK_END    = '# === GitHub IP END ==='
$HOSTS_PATH  = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$BACKUP_PATH = $HOSTS_PATH + '.bak'
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path

# 核心域名：全量测速，每个域名多个候选
$POOL = [ordered]@{
    'github.com' = @(
        '140.82.112.5','140.82.112.6','140.82.112.9','140.82.112.13','140.82.112.19',
        '140.82.113.5','140.82.113.6','140.82.113.11','140.82.113.14','140.82.113.20',
        '140.82.114.5','140.82.114.11','140.82.114.13','140.82.114.17',
        '20.205.243.166','20.27.177.113'
    )
    'api.github.com' = @(
        '140.82.112.5','140.82.112.6','140.82.112.9','140.82.112.13',
        '140.82.113.5','140.82.113.6','140.82.113.11','140.82.113.14',
        '140.82.114.5','140.82.114.6','140.82.114.11','140.82.114.13',
        '20.205.243.168','140.82.112.22','140.82.114.22'
    )
    'raw.githubusercontent.com'            = @('185.199.108.133','185.199.109.133','185.199.110.133','185.199.111.133')
    'camo.githubusercontent.com'           = @('185.199.108.133','185.199.109.133','185.199.110.133','185.199.111.133')
    'github.githubassets.com'              = @('185.199.108.215','185.199.109.215','185.199.110.215','185.199.111.215')
    'avatars.githubusercontent.com'        = @('185.199.108.133','185.199.109.133','185.199.110.133','185.199.111.133')
    'objects.githubusercontent.com'        = @('185.199.108.133','185.199.109.133','185.199.110.133','185.199.111.133')
    'codeload.github.com'                  = @('140.82.112.9','140.82.113.9','140.82.113.10','140.82.114.9','140.82.114.10','20.205.243.165')
    'user-images.githubusercontent.com'    = @('185.199.108.133','185.199.109.133','185.199.110.133')
    'release-assets.githubusercontent.com' = @('185.199.108.154','185.199.109.154','185.199.110.154','185.199.111.154')
}

# 只保留真正需要 hosts 的域名。
# 实测澄清：camo / media / private-user-images / raw.github.com / ghcr.io / npm.pkg
# 这些域名光靠 DNS 就是 3/3 稳定，写 hosts 反而把 GeoDNS 锁死了，所以全部去掉。
# 9 个核心里有 6 个其实 DNS 也够用，但写了不亏（能换成实测更快的 IP），保留。
# 真正非写不可的是 github.com、raw、release-assets —— 它们 DNS 给的那个 IP 只有 1-2/3 成功。

# ==================== 测速引擎 ====================
# 计时口径是「全链路」：TCP 建连 + TLS 握手 + 首字节。
# 实测 TLS 握手占 45%-73%，只看 TTFB 会把握手慢的 IP 排到前面 —— 用户等的是全链路。
$WORKER = {
    param($Ip, $HostName, $TimeoutMs, $Rounds)

    $samples = @()
    for ($i = 0; $i -lt $Rounds; $i++) {
        $tcp = $null; $ssl = $null
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($Ip, 443, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { continue }
            $tcp.EndConnect($iar)
            $tcp.ReceiveTimeout = $TimeoutMs
            $tcp.SendTimeout    = $TimeoutMs
            $tcpMs = [int]$sw.ElapsedMilliseconds

            $sw.Restart()
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            $ssl.ReadTimeout  = $TimeoutMs
            $ssl.WriteTimeout = $TimeoutMs
            # 显式指定 TLS 1.2（有 1.3 就一起开），不依赖系统默认值
            $proto = [System.Security.Authentication.SslProtocols]::Tls12
            try {
                if ([enum]::GetNames([System.Security.Authentication.SslProtocols]) -contains 'Tls13') {
                    $proto = $proto -bor [enum]::Parse([System.Security.Authentication.SslProtocols], 'Tls13')
                }
            }
            catch { }
            $ssl.AuthenticateAsClient($HostName, $null, $proto, $false)
            $tlsMs = [int]$sw.ElapsedMilliseconds

            $sw.Restart()
            $req = "HEAD / HTTP/1.1`r`nHost: $HostName`r`nUser-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)`r`nAccept: */*`r`nConnection: close`r`n`r`n"
            $b = [System.Text.Encoding]::ASCII.GetBytes($req)
            $ssl.Write($b, 0, $b.Length)
            $ssl.Flush()

            $buf = New-Object byte[] 512
            $n = $ssl.Read($buf, 0, $buf.Length)
            if ($n -le 0) { continue }

            $head = [System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Min($n, 16))
            if ($head -notmatch '^HTTP/') { continue }

            $ttfbMs = [int]$sw.ElapsedMilliseconds
            $samples += ($tcpMs + $tlsMs + $ttfbMs)
        }
        catch { }
        finally {
            if ($ssl) { try { $ssl.Dispose() } catch { } }
            if ($tcp) { try { $tcp.Close(); $tcp.Dispose() } catch { } }
        }
    }
    if ($samples.Count -eq 0) { return $null }
    $sorted = @($samples | Sort-Object)
    return @{ Ok = $samples.Count; Ms = $sorted[[int](($sorted.Count - 1) / 2)] }
}

# 选 IP 做网段分散：同一个 /24 的路由是同一条，4 个全落在一段里等于没有冗余。
# 第 1 名照常取最快的，后面优先挑不同 /24 的，凑不齐再按原顺序补。
function Select-DiverseIp {
    param([array]$Ranked, [int]$Count = 4)
    if ($Ranked.Count -le $Count) { return @($Ranked) }

    $picked = @()
    $used = @{}
    foreach ($ip in $Ranked) {
        if ($picked.Count -ge $Count) { break }
        $seg = ($ip -split '\.')[0..2] -join '.'
        if (-not $used.ContainsKey($seg)) {
            $picked += $ip
            $used[$seg] = $true
        }
    }
    if ($picked.Count -lt $Count) {
        foreach ($ip in $Ranked) {
            if ($picked.Count -ge $Count) { break }
            if ($picked -notcontains $ip) { $picked += $ip }
        }
    }
    return $picked
}

function Invoke-Round {
    param(
        [array]$Tasks,
        [int]$Rounds,
        [scriptblock]$OnTick,
        [int]$TimeoutMs = 0
    )
    if ($Tasks.Count -eq 0) { return @() }
    if ($TimeoutMs -le 0) { $TimeoutMs = $TIMEOUT_MS }

    $pool = [runspacefactory]::CreateRunspacePool(1, $THREADS)
    $pool.Open()
    $jobs = @()
    $out = @()
    try {
        foreach ($t in $Tasks) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($WORKER).AddArgument($t.Ip).AddArgument($t.Host).AddArgument($TimeoutMs).AddArgument($Rounds)
            $jobs += [pscustomobject]@{ PS = $ps; H = $ps.BeginInvoke(); Ip = $t.Ip; Host = $t.Host; Group = $t.Group }
        }

        $total = $jobs.Count
        $lastTick = 0
        while ($true) {
            $done = 0
            foreach ($j in $jobs) { if ($j.H.IsCompleted) { $done++ } }
            if ($OnTick -and $done -ne $lastTick) {
                $lastTick = $done
                & $OnTick $done $total
            }
            if ($done -ge $total) { break }
            Start-Sleep -Milliseconds 60
            [System.Windows.Forms.Application]::DoEvents()
        }

        foreach ($j in $jobs) {
            try {
                $r = $j.PS.EndInvoke($j.H)
                if ($r -and $r.Count -gt 0 -and $r[0]) {
                    $out += [pscustomobject]@{
                        Host  = $j.Host
                        Ip    = $j.Ip
                        Group = $j.Group
                        Ok    = [int]$r[0].Ok
                        Ms    = [int]$r[0].Ms
                        Rounds = $Rounds
                    }
                }
            }
            catch { }
        }
    }
    finally {
        # 无论正常结束还是中途抛异常，都要把 runspace 和池释放掉，否则会泄漏线程
        foreach ($j in $jobs) { try { $j.PS.Dispose() } catch { } }
        try { $pool.Close() } catch { }
        try { $pool.Dispose() } catch { }
    }
    return $out
}

# ==================== 远程候选补充 ====================
# 只采信"世界上存在这些 IP"这一个信息，绝不采信它们的测速结果
# —— 那些项目的测速跑在 GitHub Actions 的海外机器上，跟你家的宽带无关。
# 三个源并行拉取，任意一个失败只是少一份参考，不影响整体。
$FETCHER = {
    param($Url, $TimeoutSec)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout          = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
        $req.UserAgent        = 'Mozilla/5.0 L1-GitHub-Hosts'
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()
        return $text
    }
    catch { return $null }
}

function Get-RemotePool {
    param([int]$TimeoutSec = 4, [int]$MaxPerHost = 3)

    $sources = @(
        'https://raw.hellogithub.com/hosts'
        'https://cdn.jsdelivr.net/gh/ittuann/GitHub-IP-hosts@main/hosts'
        'https://hosts.gitcdn.top/hosts.txt'
    )

    $psPool = [runspacefactory]::CreateRunspacePool(1, 4)
    $psPool.Open()
    $jobs = @()
    foreach ($u in $sources) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $psPool
        [void]$ps.AddScript($FETCHER).AddArgument($u).AddArgument($TimeoutSec)
        $jobs += [pscustomobject]@{ PS = $ps; H = $ps.BeginInvoke() }
    }

    # 并行等待，期间保持界面响应
    $deadline = (Get-Date).AddSeconds($TimeoutSec + 3)
    while ($true) {
        $done = 0
        foreach ($j in $jobs) { if ($j.H.IsCompleted) { $done++ } }
        if ($done -ge $jobs.Count) { break }
        if ((Get-Date) -gt $deadline) { break }
        Start-Sleep -Milliseconds 80
        [System.Windows.Forms.Application]::DoEvents()
    }

    $texts = @()
    foreach ($j in $jobs) {
        if ($j.H.IsCompleted) {
            try {
                $r = $j.PS.EndInvoke($j.H)
                if ($r -and $r.Count -gt 0 -and $r[0]) { $texts += [string]$r[0] }
            }
            catch { }
        }
        else { try { $j.PS.Stop() } catch { } }
        try { $j.PS.Dispose() } catch { }
    }
    try { $psPool.Close() } catch { }
    try { $psPool.Dispose() } catch { }

    # 解析：只看 IP + 域名两列，域名必须是我们已经覆盖的
    $found = @{}
    foreach ($text in $texts) {
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([A-Za-z0-9][A-Za-z0-9\.\-]*[A-Za-z0-9])') {
                $ip = $Matches[1]
                $h  = $Matches[2].ToLower()
                if (-not $POOL.Contains($h)) { continue }
                if (-not $found.ContainsKey($h)) { $found[$h] = @() }
                if ($found[$h] -notcontains $ip) { $found[$h] += $ip }
            }
        }
    }

    # 去掉内置池已有的，每个域名最多补 MaxPerHost 个，避免候选爆炸拉长测速
    $added = @{}
    $newCount = 0
    foreach ($h in $found.Keys) {
        $existing = @($POOL[$h])
        $new = @()
        foreach ($ip in $found[$h]) {
            if ($existing -contains $ip) { continue }
            $new += $ip
            if ($new.Count -ge $MaxPerHost) { break }
        }
        if ($new.Count -gt 0) { $added[$h] = $new; $newCount += $new.Count }
    }

    return [pscustomobject]@{
        Added       = $added
        NewCount    = $newCount
        SourceOk    = $texts.Count
        SourceTotal = $sources.Count
    }
}

# ==================== hosts 操作 ====================
function Get-HostsContent {
    try { return [System.IO.File]::ReadAllText($HOSTS_PATH) } catch { return '' }
}

function Save-HostsBlock {
    param([string[]]$Lines, [switch]$NoBackup)

    $raw = Get-HostsContent
    if (-not $NoBackup -and (Test-Path $HOSTS_PATH)) {
        Copy-Item $HOSTS_PATH $BACKUP_PATH -Force
        # Copy-Item 会继承源文件的时间戳，导致备份文件看起来"没更新"。
        # 这里显式改成当前时间，用户一眼就能看出刚刚备份过。
        try { (Get-Item -LiteralPath $BACKUP_PATH).LastWriteTime = Get-Date } catch { }
    }

    $pattern = '(?s)\r?\n?' + [regex]::Escape($MARK_START) + '.*?' + [regex]::Escape($MARK_END) + '\r?\n?'
    $clean = [regex]::Replace($raw, $pattern, "`r`n")

    # 移除旧块后可能留下连续空行，压缩成一个，避免文件越写越松散
    $clean = [regex]::Replace($clean, '(\r\n){3,}', "`r`n`r`n")

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $block = @($MARK_START, '# Generated by local probe. Safe to delete this block.', "# $stamp") + $Lines + @($MARK_END)
    $newContent = $clean.TrimEnd() + "`r`n`r`n" + ($block -join "`r`n") + "`r`n"

    [System.IO.File]::WriteAllText($HOSTS_PATH, $newContent, [System.Text.Encoding]::Default)

    # 刷新 DNS 并把结果带回去，让界面上能看到确实执行了
    $flushOut = ''
    try { $flushOut = (ipconfig /flushdns 2>&1 | Out-String).Trim() } catch { }
    return $flushOut
}

# ---- 写入后的闭环校验 ----
# 这是整个工具最容易被忽略的一环：写进 hosts 不等于浏览器用得上。
# 有两种情况只有真跑一遍才看得见：
#   ① 写进去的首选 IP 恰好处于那 30% 的随机丢包窗口
#   ② hosts 里别的工具写了同一个域名，排在前面抢走解析
function Build-HostsLines {
    $out = @()
    foreach ($h in $script:HostMap.Keys) {
        foreach ($ip in $script:HostMap[$h]) { $out += ('{0,-16} {1}' -f $ip, $h) }
    }
    return $out
}

# 用系统解析器（会读 hosts）拿到浏览器实际会用的第一个地址
function Resolve-FirstIp {
    param([string]$HostName)
    try {
        $ips = @([System.Net.Dns]::GetHostAddresses($HostName) |
                 Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                 ForEach-Object { $_.IPAddressToString })
        if ($ips.Count -gt 0) { return $ips[0] }
    }
    catch { }
    return ''
}

# 校验工作单元：按候选顺序找一个真能连通的 IP
# 首选给两次机会 —— 这条线路约 30% 的连接会被随机打断，一次失败不代表 IP 不行
$VERIFIER = {
    param($HostName, $Candidates, $TimeoutMs)

    function Try-One {
        param($h, $ip, $t)
        $tcp = $null; $ssl = $null
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($ip, 443, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne($t, $false)) { return $false }
            $tcp.EndConnect($iar)
            $tcp.ReceiveTimeout = $t
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            $ssl.ReadTimeout = $t
            $proto = [System.Security.Authentication.SslProtocols]::Tls12
            try {
                if ([enum]::GetNames([System.Security.Authentication.SslProtocols]) -contains 'Tls13') {
                    $proto = $proto -bor [enum]::Parse([System.Security.Authentication.SslProtocols], 'Tls13')
                }
            }
            catch { }
            $ssl.AuthenticateAsClient($h, $null, $proto, $false)
            $req = "HEAD / HTTP/1.1`r`nHost: $h`r`nUser-Agent: Mozilla/5.0`r`nConnection: close`r`n`r`n"
            $b = [System.Text.Encoding]::ASCII.GetBytes($req)
            $ssl.Write($b, 0, $b.Length); $ssl.Flush()
            $buf = New-Object byte[] 256
            $n = $ssl.Read($buf, 0, $buf.Length)
            if ($n -le 0) { return $false }
            return ([System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Min(16, $buf.Length)) -match '^HTTP/')
        }
        catch { return $false }
        finally {
            if ($ssl) { try { $ssl.Dispose() } catch { } }
            if ($tcp) { try { $tcp.Close(); $tcp.Dispose() } catch { } }
        }
    }

    $idx = 0
    foreach ($ip in $Candidates) {
        $tries = if ($idx -eq 0) { 2 } else { 1 }
        for ($k = 0; $k -lt $tries; $k++) {
            if (Try-One $HostName $ip $TimeoutMs) { return @{ Ok = $true; Index = $idx; Ip = $ip } }
        }
        $idx++
        if ($idx -ge 3) { break }
    }
    return @{ Ok = $false; Index = -1; Ip = '' }
}

# 并行校验所有域名，把能用的那个提到首位；不通的只记录，不改动
function Repair-Hosts {
    param([int]$TimeoutMs = 3000)

    $res = @{ Ok = 0; Fail = @(); Conflict = @(); Rotated = @() }
    $hosts = @($script:HostMap.Keys)
    if ($hosts.Count -eq 0) { return $res }

    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min(12, $hosts.Count))
    $pool.Open()
    $jobs = @()
    $chosen = @{}
    try {
        foreach ($h in $hosts) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($VERIFIER).AddArgument($h).AddArgument($script:HostMap[$h]).AddArgument($TimeoutMs)
            $jobs += [pscustomobject]@{ PS = $ps; H = $ps.BeginInvoke(); Host = $h }
        }

        while ($true) {
            $done = 0
            foreach ($j in $jobs) { if ($j.H.IsCompleted) { $done++ } }
            $lblStatus.Text = "校验 $done/$($jobs.Count)"
            [System.Windows.Forms.Application]::DoEvents()
            if ($done -ge $jobs.Count) { break }
            Start-Sleep -Milliseconds 80
        }

        foreach ($j in $jobs) {
            try {
                $r = $j.PS.EndInvoke($j.H)
                if ($r -and $r.Count -gt 0) { $chosen[$j.Host] = $r[0] }
            }
            catch { }
        }
    }
    finally {
        foreach ($j in $jobs) { try { $j.PS.Dispose() } catch { } }
        try { $pool.Close() } catch { }
        try { $pool.Dispose() } catch { }
    }

    $changed = $false
    foreach ($h in $hosts) {
        $c = $chosen[$h]
        if (-not $c) { continue }
        if ($c.Ok) {
            $res.Ok++
            if ($c.Index -gt 0) {
                $arr = @($script:HostMap[$h])
                $pick = $arr[$c.Index]
                $script:HostMap[$h] = @($pick) + @($arr | Where-Object { $_ -ne $pick })
                $res.Rotated += $h
                $changed = $true
            }
        }
        else {
            $res.Fail += $h
        }
    }

    if ($changed) {
        $script:HostsLines = Build-HostsLines
        try { Save-HostsBlock -Lines $script:HostsLines -NoBackup | Out-Null } catch { }
        Start-Sleep -Milliseconds 150
    }

    # 纯解析层面的冲突检查：系统给的首条不是我们写的，说明有别的来源抢在前面
    foreach ($h in $hosts) {
        $ip = Resolve-FirstIp $h
        if ($ip -and (@($script:HostMap[$h]) -notcontains $ip)) { $res.Conflict += $h }
    }

    return $res
}

# ==================== 界面 ====================
$COL_BG       = [System.Drawing.Color]::FromArgb(240, 246, 243)
$COL_CARD     = [System.Drawing.Color]::White
$COL_PRIMARY  = [System.Drawing.Color]::FromArgb(16, 185, 129)
$COL_PRIMARY2 = [System.Drawing.Color]::FromArgb(5, 150, 105)
$COL_TEXT     = [System.Drawing.Color]::FromArgb(15, 23, 42)
$COL_MUTED    = [System.Drawing.Color]::FromArgb(100, 116, 139)
$COL_BORDER   = [System.Drawing.Color]::FromArgb(209, 231, 221)
$COL_OK       = [System.Drawing.Color]::FromArgb(5, 150, 105)
$COL_HEAD     = [System.Drawing.Color]::FromArgb(236, 253, 245)
$COL_ZEBRA    = [System.Drawing.Color]::FromArgb(250, 253, 251)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'L1 GitHub Hosts'
$form.Size            = New-Object System.Drawing.Size(880, 726)
$form.MinimumSize     = New-Object System.Drawing.Size(880, 726)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = $COL_BG
$form.Font            = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.ForeColor       = $COL_TEXT

# 极简图标：圆角蓝底 + 白色 L
try {
    $ico = New-Object System.Drawing.Bitmap(64, 64)
    $gfx = [System.Drawing.Graphics]::FromImage($ico)
    $gfx.SmoothingMode = 'AntiAlias'
    $gfx.Clear([System.Drawing.Color]::Transparent)

    $pth = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rr = 18
    $dd = $rr * 2
    $pth.AddArc(0, 0, $dd, $dd, 180, 90)
    $pth.AddArc(64 - $dd, 0, $dd, $dd, 270, 90)
    $pth.AddArc(64 - $dd, 64 - $dd, $dd, $dd, 0, 90)
    $pth.AddArc(0, 64 - $dd, $dd, $dd, 90, 90)
    $pth.CloseFigure()

    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(0, 0, 64, 64)),
        [System.Drawing.Color]::FromArgb(52, 211, 153),
        [System.Drawing.Color]::FromArgb(4, 120, 87),
        45.0)
    $gfx.FillPath($grad, $pth)

    $penL = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 8)
    $penL.StartCap = 'Round'
    $penL.EndCap = 'Round'
    $gfx.DrawLine($penL, 24, 18, 24, 46)
    $gfx.DrawLine($penL, 24, 46, 46, 46)

    # 先取 HICON 再逐个释放，否则这些 GDI 句柄会一直挂到进程退出
    $form.Icon = [System.Drawing.Icon]::FromHandle($ico.GetHicon())
    $penL.Dispose()
    $grad.Dispose()
    $pth.Dispose()
    $gfx.Dispose()
    $ico.Dispose()
}
catch { }

function Get-RoundedPath {
    param([int]$W, [int]$H, [int]$R)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($W - $d, 0, $d, $d, 270, 90)
    $p.AddArc($W - $d, $H - $d, $d, $d, 0, 90)
    $p.AddArc(0, $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text     = 'L1 GitHub Hosts'
$lblTitle.Font     = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $COL_TEXT
$lblTitle.Location = New-Object System.Drawing.Point(24, 16)
$lblTitle.Size     = New-Object System.Drawing.Size(400, 34)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = '本机实测 · 每次都是全新测速'
$lblSub.ForeColor = $COL_PRIMARY2
$lblSub.Location  = New-Object System.Drawing.Point(26, 52)
$lblSub.Size      = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblSub)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = '就绪'
$lblStatus.ForeColor = $COL_MUTED
$lblStatus.TextAlign = 'MiddleRight'
$lblStatus.Location  = New-Object System.Drawing.Point(430, 20)
$lblStatus.Size      = New-Object System.Drawing.Size(410, 30)
$lblStatus.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(26, 80)
$progress.Size     = New-Object System.Drawing.Size(812, 8)
$progress.Style    = 'Continuous'
$form.Controls.Add($progress)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location            = New-Object System.Drawing.Point(26, 100)
$grid.Size                = New-Object System.Drawing.Size(812, 400)
$grid.BackgroundColor     = $COL_CARD
$grid.BorderStyle         = 'None'
$grid.AllowUserToAddRows  = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly            = $true
$grid.RowHeadersVisible   = $false
$grid.SelectionMode       = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.GridColor           = $COL_BORDER
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersHeight = 34
$grid.ColumnHeadersDefaultCellStyle.BackColor = $COL_HEAD
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $COL_PRIMARY2
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = $COL_HEAD
$grid.DefaultCellStyle.BackColor = $COL_CARD
$grid.DefaultCellStyle.ForeColor = $COL_TEXT
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(209, 250, 229)
$grid.DefaultCellStyle.SelectionForeColor = $COL_TEXT
$grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
$grid.RowTemplate.Height = 30
$grid.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$grid.AlternatingRowsDefaultCellStyle.BackColor = $COL_ZEBRA
$grid.CellBorderStyle = 'SingleHorizontal'
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(209, 250, 229)

[void]$grid.Columns.Add('Host', '域名')
[void]$grid.Columns.Add('Ip', 'IP 地址')
[void]$grid.Columns.Add('Ms', '全链路')
[void]$grid.Columns.Add('Stable', '稳定性')
[void]$grid.Columns.Add('State', '状态')
$grid.Columns['Host'].FillWeight   = 42
$grid.Columns['Ip'].FillWeight     = 22
$grid.Columns['Ms'].FillWeight     = 14
$grid.Columns['Stable'].FillWeight = 12
$grid.Columns['State'].FillWeight  = 12
foreach ($c in @('Ms','Stable','State')) { $grid.Columns[$c].DefaultCellStyle.Alignment = 'MiddleCenter' }
$grid.Columns['Host'].DefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$form.Controls.Add($grid)

$btnProbe = New-Object System.Windows.Forms.Button
$btnProbe.Text      = '开始测速'
$btnProbe.Location  = New-Object System.Drawing.Point(26, 514)
$btnProbe.Size      = New-Object System.Drawing.Size(150, 40)
$btnProbe.FlatStyle = 'Flat'
$btnProbe.FlatAppearance.BorderSize = 0
$btnProbe.BackColor = $COL_PRIMARY
$btnProbe.ForeColor = [System.Drawing.Color]::White
$btnProbe.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$btnProbe.Cursor    = 'Hand'
$rgnProbe = Get-RoundedPath 150 40 12
$btnProbe.Region = New-Object System.Drawing.Region($rgnProbe)
$rgnProbe.Dispose()
$btnProbe.Add_MouseEnter({ if (-not $script:Busy) { $btnProbe.BackColor = $COL_PRIMARY2 } })
$btnProbe.Add_MouseLeave({ if (-not $script:Busy) { $btnProbe.BackColor = $COL_PRIMARY } })
$form.Controls.Add($btnProbe)

function New-SecondaryButton($text, $x, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Location  = New-Object System.Drawing.Point($x, 514)
    $b.Size      = New-Object System.Drawing.Size($w, 40)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $COL_BORDER
    $b.BackColor = $COL_CARD
    $b.ForeColor = $COL_TEXT
    $b.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $b.Cursor    = 'Hand'
    $b.Enabled   = $false
    $rgnBtn = Get-RoundedPath $w 40 12
    $b.Region = New-Object System.Drawing.Region($rgnBtn)
    $rgnBtn.Dispose()
    $b.Add_MouseEnter({ if ($this.Enabled) { $this.BackColor = $COL_HEAD } })
    $b.Add_MouseLeave({ $this.BackColor = $COL_CARD })
    return $b
}

$btnApply     = New-SecondaryButton '写入 hosts'  186 116
$btnOpenHosts = New-SecondaryButton '打开 hosts'  310 116
$btnSave      = New-SecondaryButton '保存报告'    434 116
$btnReport    = New-SecondaryButton '打开报告'    558 116
$btnDefault   = New-SecondaryButton '恢复初始'    682 116
$form.Controls.AddRange(@($btnApply, $btnOpenHosts, $btnSave, $btnReport, $btnDefault))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location   = New-Object System.Drawing.Point(26, 566)
$txtLog.Size       = New-Object System.Drawing.Size(812, 78)
$txtLog.Multiline  = $true
$txtLog.ReadOnly   = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BorderStyle = 'FixedSingle'
$txtLog.BackColor  = $COL_ZEBRA
$txtLog.ForeColor  = $COL_MUTED
$txtLog.Font       = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$form.Controls.Add($txtLog)

function Write-Log($msg) {
    $ts = Get-Date -Format 'HH:mm:ss'
    $txtLog.AppendText("[$ts] $msg`r`n")

    # 长时间开着反复测速时，日志会一直涨。只保留最近 400 行。
    $lines = $txtLog.Lines
    if ($lines.Count -gt 400) {
        $keep = $lines[($lines.Count - 400)..($lines.Count - 1)]
        $txtLog.Text = ($keep -join "`r`n") + "`r`n"
    }

    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# 把写入失败翻译成人话：用户看到"拒绝访问"不知道下一步该做什么
function Format-WriteError {
    param($Err)
    $msg = ''
    if ($Err -is [System.Management.Automation.ErrorRecord]) { $msg = $Err.Exception.Message } else { $msg = [string]$Err }

    if ($Err.Exception -is [System.UnauthorizedAccessException] -or $msg -match '拒绝访问|Access is denied|UnauthorizedAccess') {
        return "没有写入权限。请确认程序是以管理员身份运行的；如果已经是，通常是安全软件拦截了对 hosts 的修改，临时退出 360 / 火绒后再试。"
    }
    if ($msg -match '正由另一进程使用|being used by another process|共享冲突|sharing violation') {
        return "hosts 文件正被其它程序占用（常见于安全软件实时防护）。等几秒重试，或临时关闭防护再写入。"
    }
    if ($msg -match '找不到路径|Could not find a part of the path|path is not') {
        return "hosts 文件不存在或路径不可用，可能系统盘符异常。"
    }
    if ($msg -match '磁盘空间|not enough space|There is not enough space') {
        return "磁盘空间不足，无法写入 hosts。"
    }
    return $msg
}

# 界面内提示：显示在右上角状态栏，3.5 秒后自动恢复，不打断操作
$script:StatusDefault = '就绪'
$script:ToastTimer = New-Object System.Windows.Forms.Timer
$script:ToastTimer.Interval = 3500
$script:ToastTimer.Add_Tick({
    $script:ToastTimer.Stop()
    $lblStatus.Text = $script:StatusDefault
    $lblStatus.ForeColor = $COL_MUTED
})

function Show-Toast {
    param([string]$Msg, [string]$Kind = 'muted')
    $c = switch ($Kind) {
        'ok'    { $COL_OK }
        'warn'  { [System.Drawing.Color]::FromArgb(180, 120, 20) }
        'err'   { [System.Drawing.Color]::FromArgb(200, 60, 60) }
        default { $COL_MUTED }
    }
    $lblStatus.Text = $Msg
    $lblStatus.ForeColor = $c
    Write-Log $Msg
    $script:ToastTimer.Stop()
    $script:ToastTimer.Start()
    [System.Windows.Forms.Application]::DoEvents()
}

# 运行态数据
$script:Results = @()
$script:HostsLines = @()
$script:HostMap = [ordered]@{}
$script:LastReport = ''
$script:SourceInfo = '内置池'
$script:Busy = $false
$script:Verifying = $false

# ==================== 测速主流程 ====================
function Start-Probe {
    # 校验过程中会改写 hosts，这时如果再跑测速会互相覆盖，直接挡住
    if ($script:Busy -or $script:Verifying) { return }
    $script:Busy = $true
    # 上一轮的报告已经和新结果对不上，先作废；按钮统一在下面禁用
    $script:LastReport = ''
    $btnProbe.Text = '测速中...'
    $btnProbe.BackColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $btnApply.Enabled = $false
    foreach ($b in @($btnSave, $btnOpenHosts, $btnReport, $btnDefault)) { $b.Enabled = $false }
    $grid.Rows.Clear()
    $script:Results = @()
    $progress.Value = 0
    $swAll = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # ---- 远程补充候选（失败就跳过，不影响使用）----
        $merged = @{}
        foreach ($h in $POOL.Keys) { $merged[$h] = @($POOL[$h]) }
        $script:SourceInfo = '内置池'

        if (-not $NoRemote) {
            $lblStatus.Text = '拉取远程候选'
            $progress.Value = 2
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $remote = Get-RemotePool
                if ($remote.NewCount -gt 0) {
                    foreach ($h in $remote.Added.Keys) { $merged[$h] = @($merged[$h]) + $remote.Added[$h] }
                    $script:SourceInfo = ('内置池 + 远程补充 {0} 个（{1}/{2} 源可达）' -f $remote.NewCount, $remote.SourceOk, $remote.SourceTotal)
                    Write-Log ("远程源补充 {0} 个新 IP（{1}/{2} 个源可达）" -f $remote.NewCount, $remote.SourceOk, $remote.SourceTotal)
                }
                elseif ($remote.SourceOk -eq 0) {
                    Write-Log '远程源全部不可达，只用内置池'
                }
                else {
                    Write-Log ("远程源没有新 IP（{0}/{1} 个源可达）" -f $remote.SourceOk, $remote.SourceTotal)
                }
            }
            catch {
                Write-Log ('远程补充跳过：' + $_.Exception.Message.Split([char]10)[0])
            }
        }

        # ---- 组装任务 ----
        $tasks = @()
        foreach ($h in $POOL.Keys) {
            foreach ($ip in $merged[$h]) { $tasks += [pscustomobject]@{ Ip = $ip; Host = $h; Group = 'core' } }
        }
        Write-Log ("核心域名 {0} 个，候选 {1} 个" -f $POOL.Keys.Count, $tasks.Count)
        $lblStatus.Text = '粗筛中'
        [System.Windows.Forms.Application]::DoEvents()

        # ---- 阶段一：单次粗筛 ----
        $phase1 = Invoke-Round -Tasks $tasks -Rounds 1 -OnTick {
            param($d, $t)
            $progress.Value = [int]($d / $t * 38)
            $lblStatus.Text = "粗筛 $d/$t"
        }

        $alive = @($phase1 | Where-Object { $_.Ok -ge 1 })
        $dead  = @($phase1 | Where-Object { $_.Ok -lt 1 })
        Write-Log ("粗筛通过 {0} 个，失败 {1} 个" -f $alive.Count, $dead.Count)

        # ---- 阶段一补测：失败的不直接淘汰 ----
        # 这条线路实测有约 30% 的连接会被随机打断，一次超时不代表 IP 不行。
        # 给一次长超时的机会，能把被误杀的好 IP 救回来一大半。
        if ($dead.Count -gt 0) {
            $lblStatus.Text = '补测失败候选'
            $progress.Value = 39
            [System.Windows.Forms.Application]::DoEvents()
            $retry = Invoke-Round -Tasks $dead -Rounds 1 -TimeoutMs 5000 -OnTick {
                param($d, $t)
                $progress.Value = 39 + [int]($d / $t * 9)
                $lblStatus.Text = "补测 $d/$t"
            }
            $recovered = @($retry | Where-Object { $_.Ok -ge 1 })
            if ($recovered.Count -gt 0) {
                Write-Log ("补测救回 {0} 个候选（首轮被随机丢包误杀）" -f $recovered.Count)
                $alive = @($alive + $recovered)
            }
        }
        Write-Log ("进入确认阶段：{0} 个候选" -f $alive.Count)

        # ---- 阶段二：再测两轮确认稳定性 ----
        $final = @()
        if ($alive.Count -gt 0) {
            $lblStatus.Text = '确认中'
            $confirmTasks = $alive | ForEach-Object { [pscustomobject]@{ Ip = $_.Ip; Host = $_.Host; Group = $_.Group } }
            $phase2 = Invoke-Round -Tasks $confirmTasks -Rounds ($ATTEMPTS - 1) -OnTick {
                param($d, $t)
                $progress.Value = 48 + [int]($d / $t * 50)
                $lblStatus.Text = "确认 $d/$t"
            }

            $map = @{}
            foreach ($r in $phase2) { $map["$($r.Host)|$($r.Ip)"] = $r }
            foreach ($a in $alive) {
                $k = "$($a.Host)|$($a.Ip)"
                if ($map.ContainsKey($k)) {
                    $final += [pscustomobject]@{
                        Host = $a.Host; Ip = $a.Ip
                        Ok = 1 + $map[$k].Ok
                        Ms = $map[$k].Ms
                        Group = $a.Group
                    }
                }
            }
        }

        $swAll.Stop()
        $progress.Value = 100

        # ---- 排序：核心优先，组内先看成功率再看耗时 ----
        $script:Results = @($final |
            Sort-Object @{Expression={ if ($_.Group -eq 'core') { 0 } else { 1 } }},
                          @{Expression='Host'; Ascending=$true},
                          @{Expression='Ok'; Descending=$true},
                          @{Expression='Ms'; Ascending=$true})

        # ---- 填充表格 ----
        $grid.SuspendLayout()
        $shown = @{}
        foreach ($r in $script:Results) {
            $stable = '{0}/{1}' -f $r.Ok, $ATTEMPTS
            if ($r.Ok -ge $ATTEMPTS) { $state = '稳定' }
            elseif ($r.Ok -ge ($ATTEMPTS - 1)) { $state = '一般' }
            else { $state = '较弱' }
            $idx = $grid.Rows.Add($r.Host, $r.Ip, ('{0} ms' -f $r.Ms), $stable, $state)
            if (-not $shown.ContainsKey($r.Host)) {
                $shown[$r.Host] = $true
                $grid.Rows[$idx].DefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
            }
            if ($state -eq '稳定') { $grid.Rows[$idx].Cells['State'].Style.ForeColor = $COL_OK }
            elseif ($state -eq '一般') { $grid.Rows[$idx].Cells['State'].Style.ForeColor = [System.Drawing.Color]::FromArgb(180, 120, 20) }
            else { $grid.Rows[$idx].Cells['State'].Style.ForeColor = [System.Drawing.Color]::FromArgb(190, 70, 60) }
        }
        $grid.ResumeLayout()

        # ---- 生成待写入内容：每个域名取最优 4 个，并做网段分散 ----
        # 单次连接实测成功率约 70%，全失败概率：写 2 个是 9%，写 4 个只有 0.8%。
        # Windows 按 hosts 文件顺序返回地址，Chrome / curl 首个连不上会自动试下一个。
        $script:HostMap = [ordered]@{}
        foreach ($h in ($script:Results | Group-Object Host)) {
            $ranked = @($h.Group | ForEach-Object { $_.Ip })
            $script:HostMap[$h.Name] = Select-DiverseIp -Ranked $ranked -Count 4
        }
        $script:HostsLines = Build-HostsLines

        $elapsed = $swAll.Elapsed.TotalSeconds
        $usable = ($script:Results | Group-Object Host).Count
        Write-Log ("完成：{0} 个域名有可用 IP，耗时 {1:N1} 秒" -f $usable, $elapsed)
        $lblStatus.Text = ('完成 · {0} 个域名 · {1:N1}s' -f $usable, $elapsed)

        $btnSave.Enabled = $true
        $btnApply.Enabled = $true
        foreach ($b in @($btnOpenHosts, $btnDefault)) { $b.Enabled = $true }
    }
    catch {
        Write-CrashLog '测速流程' $_
        Write-Log ('出错：' + $_.Exception.Message)
        $lblStatus.Text = '出错'
    }
    finally {
        $btnProbe.Text = '重新测速'
        $btnProbe.BackColor = $COL_PRIMARY
        $script:Busy = $false
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ==================== 生成报告 ====================
function Save-Report {
    param([string]$OutDir = '')

    $desktop = $OutDir
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path $desktop)) {
            $desktop = Join-Path $env:USERPROFILE 'Desktop'
        }
    }
    $outPath = Join-Path $desktop ('GitHub可用IP_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    $sb = New-Object System.Text.StringBuilder
    $bar = '=' * 60
    $thin = '-' * 60

    [void]$sb.AppendLine($bar)
    [void]$sb.AppendLine('  GitHub 可用 IP 测速报告')
    [void]$sb.AppendLine($bar)
    [void]$sb.AppendLine(('  测速时间 : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('  本机名称 : {0}' -f $env:COMPUTERNAME))
    [void]$sb.AppendLine('  测速指标 : 全链路 = TCP 建连 + TLS 握手 + 首字节')
    [void]$sb.AppendLine('  排序规则 : 先看成功率，再看全链路耗时')
    [void]$sb.AppendLine(('  候选来源 : {0}' -f $script:SourceInfo))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('  一、可直接复制到 hosts 的内容')
    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  把下面整段追加到 hosts 文件末尾：')
    [void]$sb.AppendLine('  C:\Windows\System32\drivers\etc\hosts')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  ' + $MARK_START)
    foreach ($line in $script:HostsLines) { [void]$sb.AppendLine('  ' + $line) }
    [void]$sb.AppendLine('  ' + $MARK_END)
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('  二、后续怎么改')
    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【1】hosts 文件在哪')
    [void]$sb.AppendLine('    C:\Windows\System32\drivers\etc\hosts')
    [void]$sb.AppendLine('    右键用记事本打开 hosts 文件')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【2】改完必须刷新 DNS')
    [void]$sb.AppendLine('    Win + R 键 → 输入 cmd → 输入')
    [void]$sb.AppendLine('    ipconfig /flushdns')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【3】浏览器 DNS 缓存')
    [void]$sb.AppendLine('    Chrome / Edge：地址栏输入')
    [void]$sb.AppendLine('    chrome://net-internals/#dns')
    [void]$sb.AppendLine('    点上面的 "Clear host cache"')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('    Firefox：')
    [void]$sb.AppendLine('    about:networking#dns')
    [void]$sb.AppendLine('    点 "Clear DNS Cache"')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【4】想撤销本工具的改动')
    [void]$sb.AppendLine('    方式一  点程序上的"恢复初始"按钮')
    [void]$sb.AppendLine('    方式二  删掉 hosts 里 BEGIN 到 END 这一整段')
    [void]$sb.AppendLine('    方式三  把 hosts.bak 复制成 hosts 覆盖')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【5】备份在哪')
    [void]$sb.AppendLine('    C:\Windows\System32\drivers\etc\hosts.bak')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('  【6】一个提醒')
    [void]$sb.AppendLine('    gist.github.com 这类域名 DNS 被投毒，换 IP 也连不上，')
    [void]$sb.AppendLine('    hosts 解决不了，需要代理。')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('  三、各域名 IP 排名（供参考）')
    [void]$sb.AppendLine($thin)
    [void]$sb.AppendLine('')
    foreach ($g in ($script:Results | Group-Object Host)) {
        [void]$sb.AppendLine(('  {0}   （{1} 个可用）' -f $g.Name, $g.Count))
        $rank = 1
        foreach ($r in $g.Group) {
            $mark = ''
            if ($rank -eq 1) { $mark = '   <== 最优' }
            [void]$sb.AppendLine(('    {0,2}. {1,-16} {2,5} ms   成功 {3}/{4}{5}' -f $rank, $r.Ip, $r.Ms, $r.Ok, $ATTEMPTS, $mark))
            $rank++
        }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine($bar)

    try {
        $sb.ToString() | Out-File -FilePath $outPath -Encoding UTF8
        return $outPath
    }
    catch { return '' }
}

# ==================== 事件 ====================
$btnProbe.Add_Click({ Start-Probe })

$btnApply.Add_Click({
    if ($script:HostsLines.Count -eq 0) { return }
    if ($script:Verifying) { return }
    $script:Verifying = $true
    try {
        $flush = Save-HostsBlock -Lines $script:HostsLines
        $btnOpenHosts.Enabled = $true
        Write-Log ('已写入 {0} 条，DNS 已刷新' -f $script:HostsLines.Count)

        # ---- 写完之后必须验一遍 ----
        # 写进去 ≠ 浏览器用得上。下面这一步会按系统实际解析结果跑完整链路，
        # 不通就把该域名的候选轮换一位重写，最多试 3 轮。
        $total = $script:HostMap.Keys.Count
        if ($total -gt 0) {
            $lblStatus.Text = '校验中'
            [System.Windows.Forms.Application]::DoEvents()

            # 校验自己失败不能算成"写入失败"——hosts 其实已经写进去了
            $vr = $null
            try { $vr = Repair-Hosts }
            catch {
                Write-CrashLog '写入后校验' $_
                Write-Log ('hosts 已写入，但校验过程出错：' + $_.Exception.Message)
                Show-Toast '已写入，校验未完成' 'warn'
            }

            if ($vr) {
                if ($vr.Fail.Count -eq 0) {
                    Show-Toast ('已写入并校验通过（{0}/{1} 个域名）' -f $vr.Ok, $total) 'ok'
                    Write-Log ('校验通过：{0}/{1} 个域名可正常访问' -f $vr.Ok, $total)
                    $lblStatus.Text = ('已写入 · 校验通过 {0}/{1}' -f $vr.Ok, $total)
                }
                else {
                    Show-Toast ('已写入，{0}/{1} 个域名校验通过' -f $vr.Ok, $total) 'warn'
                    Write-Log ('校验未通过：' + ($vr.Fail -join '、'))
                    $lblStatus.Text = ('已写入 · 校验 {0}/{1}' -f $vr.Ok, $total)
                    if ($vr.Conflict.Count -gt 0) {
                        Write-Log ('hosts 里有其它来源的重复条目，解析被它们抢走：' + ($vr.Conflict -join '、') + '。建议先点「恢复初始」再写入。')
                    }
                }
                if ($vr.Rotated.Count -gt 0) {
                    Write-Log ('以下域名的首选 IP 当场不可用，已自动换成下一条：' + ($vr.Rotated -join '、'))
                }
            }
        }
        else {
            Show-Toast ('已写入 {0} 条，DNS 已刷新' -f $script:HostsLines.Count) 'ok'
        }
    }
    catch {
        Write-CrashLog '写入 hosts' $_
        $friendly = Format-WriteError $_
        Write-Log ('写入失败：' + $friendly)
        [System.Windows.Forms.MessageBox]::Show($friendly, '写入失败', 'OK', 'Error') | Out-Null
    }
    finally {
        $script:Verifying = $false
    }
})

$btnOpenHosts.Add_Click({
    # 先把待写入的内容放进剪贴板，打开记事本直接 Ctrl+V 就能粘贴
    if ($script:HostsLines.Count -gt 0) {
        try {
            $blk = (@($MARK_START) + $script:HostsLines + @($MARK_END)) -join "`r`n"
            [System.Windows.Forms.Clipboard]::SetText($blk)
            Show-Toast '已复制 hosts 内容到剪贴板' 'ok'
        }
        catch { }
    }
    try { Start-Process notepad.exe -ArgumentList $HOSTS_PATH } catch { }
})

$btnSave.Add_Click({
    if ($script:Results.Count -eq 0) {
        Show-Toast '请先点「重新测速」' 'warn'
        return
    }
    try {
        $path = Save-Report
        if ($path -and (Test-Path $path)) {
            $script:LastReport = $path
            $btnReport.Enabled = $true
            Show-Toast '报告已保存至桌面' 'ok'
        }
        else {
            Show-Toast '保存失败，请检查桌面是否可写' 'err'
        }
    }
    catch {
        Write-CrashLog '保存报告' $_
        Show-Toast ('保存出错：' + $_.Exception.Message) 'err'
    }
})

$btnReport.Add_Click({
    try {
        if ($script:LastReport -and (Test-Path $script:LastReport)) { Start-Process $script:LastReport }
        else { Show-Toast '报告文件已不存在，请重新保存' 'warn' }
    }
    catch {
        Write-CrashLog '打开报告' $_
        Show-Toast ('打开报告失败：' + $_.Exception.Message) 'err'
    }
})

$btnDefault.Add_Click({
    $msg = "将把 hosts 恢复成 Windows 初始状态，删除所有自定义条目（包括本工具和其它工具写入的）。`r`n`r`n当前内容会先备份到：`r`n{0}`r`n`r`n确定继续吗？" -f $BACKUP_PATH
    $r = [System.Windows.Forms.MessageBox]::Show($msg, '恢复初始状态', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    try {
        if (Test-Path $HOSTS_PATH) {
            Copy-Item $HOSTS_PATH $BACKUP_PATH -Force
            try { (Get-Item -LiteralPath $BACKUP_PATH).LastWriteTime = Get-Date } catch { }
        }

        $defLines = @(
            '# Copyright (c) 1993-2009 Microsoft Corp.'
            '#'
            '# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.'
            '#'
            '# This file contains the mappings of IP addresses to host names. Each'
            '# entry should be kept on an individual line. The IP address should'
            '# be placed in the first column followed by the corresponding host name.'
            '# The IP address and the host name should be separated by at least one'
            '# space.'
            '#'
            '# Additionally, comments (such as these) may be inserted on individual'
            '# lines or following the machine name denoted by a ''#'' symbol.'
            '#'
            '# For example:'
            '#'
            '#      102.54.94.97     rhino.acme.com          # source server'
            '#       38.25.63.10     x.acme.com              # x client host'
            ''
            '# localhost name resolution is handled within DNS itself.'
            "#`t127.0.0.1       localhost"
            "#`t::1             localhost"
            ''
        )
        $defText = ($defLines -join "`r`n")
        [System.IO.File]::WriteAllText($HOSTS_PATH, $defText, [System.Text.Encoding]::Default)

        try { ipconfig /flushdns 2>&1 | Out-Null } catch { }
        Show-Toast 'hosts 已恢复初始状态，DNS 已刷新' 'ok'
    }
    catch {
        Write-CrashLog '恢复初始' $_
        $friendly = Format-WriteError $_
        Write-Log ('恢复失败：' + $friendly)
        Show-Toast '恢复失败，详见日志' 'err'
    }
})

# ==================== 屏幕适配 ====================
# 界面按 880x726 设计。小屏笔记本 + 系统缩放（常见于 1366x768 @125%）时，
# 逻辑可用区域会比这个小，底部按钮会被切到屏幕外。
# 这里等比缩小所有控件而不是让它们溢出 —— 宁可字小一点，也不能点不到按钮。
try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maxW = $wa.Width - 24
    $maxH = $wa.Height - 24
    if ($form.Width -gt $maxW -or $form.Height -gt $maxH) {
        # 必须显式转 double：PS 里 880/880 会得到 Int32 的 1，
        # 此时 [Math]::Min(1, 0.77) 会选 Int32 重载把 0.77 四舍五入成 1，导致完全不缩放。
        # 另外按客户区算，边框不参与缩放，否则小尺寸下会差出十几像素。
        $bw = $form.Width  - $form.ClientSize.Width
        $bh = $form.Height - $form.ClientSize.Height
        $cw = $form.ClientSize.Width
        $ch = $form.ClientSize.Height
        $s = [Math]::Min([double]($maxW - $bw) / $cw, [double]($maxH - $bh) / $ch)
        if ($s -lt 0.5) { $s = 0.5 }
        if ($s -ge 1) { $s = 1 }
        foreach ($c in $form.Controls) {
            $c.Location = New-Object System.Drawing.Point([int]($c.Left * $s), [int]($c.Top * $s))
            $c.Size     = New-Object System.Drawing.Size([int]($c.Width * $s), [int]($c.Height * $s))
        }
        $form.MinimumSize = New-Object System.Drawing.Size(320, 240)
        $form.ClientSize = New-Object System.Drawing.Size([int]($cw * $s), [int]($ch * $s))
        $form.MinimumSize = $form.Size
        Write-Log ('屏幕可用区域 {0}x{1}，界面按 {2:P0} 缩放' -f $wa.Width, $wa.Height, $s)
    }
}
catch { Write-CrashLog '屏幕适配' $_ }

# ==================== 启动 ====================
$form.Add_Shown({
    Write-Log '点「重新测速」按钮，大约需要 20-30 秒'
    if ($script:PrevRun) {
        Write-Log ('上次运行没有正常退出（' + $script:PrevRun + ' 启动），可能是被安全软件结束或程序崩溃')
    }
    $pos = Get-HostsContent
    if ($pos -match [regex]::Escape($MARK_START)) {
        Write-Log 'hosts 里已有本工具写入的配置，重新测速会覆盖它'
    }
})

if ($StressTest) {
    # 边界场景压测：全部走真实代码路径，只是把 hosts 指向临时文件
    $rows = New-Object System.Collections.ArrayList
    function Add-Case {
        param([string]$Name, [bool]$Ok, [string]$Detail)
        [void]$rows.Add([pscustomobject]@{
            检查项 = $Name
            结果   = $(if ($Ok) { 'PASS' } else { 'FAIL' })
            说明   = $Detail
        })
    }

    # --- 1. 断网：所有候选都连不上 ---
    try {
        $dead = @(
            [pscustomobject]@{ Ip = '192.0.2.1'; Host = 'github.com'; Group = 'core' },
            [pscustomobject]@{ Ip = '192.0.2.2'; Host = 'github.com'; Group = 'core' }
        )
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = @(Invoke-Round -Tasks $dead -Rounds 1 -TimeoutMs 600)
        $sw.Stop()
        Add-Case '断网/全失败探测' ($r.Count -eq 0) ('返回 {0} 条，耗时 {1:N1}s' -f $r.Count, $sw.Elapsed.TotalSeconds)
    }
    catch { Add-Case '断网/全失败探测' $false $_.Exception.Message }

    # --- 2~4. hosts 写入的三种边界，全部指向临时文件，不碰真实 hosts ---
    $origHosts  = $HOSTS_PATH
    $origBak    = $BACKUP_PATH
    $tmpHosts   = Join-Path $env:TEMP 'L1GH_stress_hosts.txt'
    $HOSTS_PATH  = $tmpHosts
    $BACKUP_PATH = $tmpHosts + '.bak'

    try {
        [System.IO.File]::WriteAllText($tmpHosts, "# base`r`n", [System.Text.Encoding]::Default)
        $null = Save-HostsBlock -Lines @('1.1.1.1  github.com')
        $txt = [System.IO.File]::ReadAllText($tmpHosts)
        Add-Case 'hosts 正常写入' ($txt.Contains($MARK_START) -and $txt.Contains('1.1.1.1')) '标记与条目都写入'
    }
    catch { Add-Case 'hosts 正常写入' $false $_.Exception.Message }

    try {
        $threw = $false
        $fs = [System.IO.File]::Open($tmpHosts, 'Open', 'ReadWrite', 'None')
        try { $null = Save-HostsBlock -Lines @('2.2.2.2  github.com') } catch { $threw = $true }
        $fs.Close()
        Add-Case 'hosts 被占用' $threw '正确抛出异常，界面会提示失败'
    }
    catch { Add-Case 'hosts 被占用' $false $_.Exception.Message }

    try {
        Set-ItemProperty -LiteralPath $tmpHosts -Name IsReadOnly -Value $true
        $threw = $false
        try { $null = Save-HostsBlock -Lines @('3.3.3.3  github.com') } catch { $threw = $true }
        Set-ItemProperty -LiteralPath $tmpHosts -Name IsReadOnly -Value $false
        Add-Case 'hosts 只读' $threw '正确抛出异常'
    }
    catch { Add-Case 'hosts 只读' $false $_.Exception.Message }

    $HOSTS_PATH  = $origHosts
    $BACKUP_PATH = $origBak
    Remove-Item $tmpHosts, ($tmpHosts + '.bak') -Force -ErrorAction SilentlyContinue

    # --- 5. 空候选写 hosts ---
    try {
        $script:HostMap = [ordered]@{}
        $lines = @(Build-HostsLines)
        Add-Case '空候选写 hosts' ($lines.Count -eq 0) '返回 0 行，不抛异常'
    }
    catch { Add-Case '空候选写 hosts' $false $_.Exception.Message }

    # --- 6. IP 选择边界 ---
    try {
        $a = @(Select-DiverseIp -Ranked @() -Count 4)
        $b = @(Select-DiverseIp -Ranked @('1.1.1.1') -Count 4)
        $c = @(Select-DiverseIp -Ranked @('1.1.1.1', '2.2.2.2') -Count 4)
        $d = @(Select-DiverseIp -Ranked @('1.1.1.1', '1.1.1.2', '1.1.1.3', '1.1.1.4', '1.1.1.5') -Count 4)
        $ok = ($a.Count -eq 0 -and $b.Count -eq 1 -and $c.Count -eq 2 -and $d.Count -eq 4)
        Add-Case 'IP 选择边界' $ok ('空={0} 1个={1} 2个={2} 同段5个={3}' -f $a.Count, $b.Count, $c.Count, $d.Count)
    }
    catch { Add-Case 'IP 选择边界' $false $_.Exception.Message }

    # --- 7. 崩溃日志自身不能崩 ---
    try {
        Write-CrashLog '压测-空异常' $null
        Write-CrashLog '压测-异常对象' (New-Object System.Exception('stress test'))
        Add-Case '崩溃日志写入' $true ('写入 ' + $LOG_FILE)
    }
    catch { Add-Case '崩溃日志写入' $false $_.Exception.Message }

    # --- 8. 没有任何结果时保存报告 ---
    try {
        $script:Results = @()
        $script:HostsLines = @()
        $script:SourceInfo = '压测'
        $p = Save-Report -OutDir $env:TEMP
        $ok = ($p -and (Test-Path $p))
        if ($ok) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        Add-Case '空结果保存报告' $ok $(if ($ok) { '文件已生成并清理' } else { '未生成文件' })
    }
    catch { Add-Case '空结果保存报告' $false $_.Exception.Message }

    # --- 9. 目标目录不可写（拿一个普通文件当目录用，必定失败）---
    try {
        $notDir = Join-Path $env:TEMP 'L1GH_notadir'
        [System.IO.File]::WriteAllText($notDir, 'x')
        $p = Save-Report -OutDir $notDir
        Remove-Item $notDir -Force -ErrorAction SilentlyContinue
        Add-Case '目录不可写保存报告' ([string]::IsNullOrEmpty($p)) $(if ($p) { '意外写成功了' } else { '返回空，界面提示失败' })
    }
    catch { Add-Case '目录不可写保存报告' $true '抛出异常且已被捕获' }

    ''
    '================== 边界压测结果 =================='
    $rows | Format-Table -AutoSize | Out-String -Width 110
    $failCount = @($rows | Where-Object { $_.结果 -eq 'FAIL' }).Count
    ('通过 {0} / {1}，失败 {2}' -f ($rows.Count - $failCount), $rows.Count, $failCount)
    $form.Dispose()
    exit $(if ($failCount -gt 0) { 1 } else { 0 })
}

if ($DryRun) {
    # 端到端自检：完整跑一遍 测速 → 写 hosts → 校验 → 出报告，
    # 但 hosts 指向临时文件，不碰系统的。
    $origHosts  = $HOSTS_PATH
    $origBak    = $BACKUP_PATH
    $tmpHosts   = Join-Path $env:TEMP 'L1GH_dryrun_hosts.txt'
    [System.IO.File]::WriteAllText($tmpHosts, "# dryrun base`r`n", [System.Text.Encoding]::Default)
    $HOSTS_PATH  = $tmpHosts
    $BACKUP_PATH = $tmpHosts + '.bak'

    $swAll = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Start-Probe
    }
    catch {
        Write-CrashLog '端到端自检-测速' $_
        "测速阶段抛异常: $($_.Exception.Message)"
    }
    $swAll.Stop()

    ''
    '================== 1. 测速 =================='
    "  结果条数 : $($script:Results.Count)"
    "  总耗时   : $([int]$swAll.Elapsed.TotalSeconds) 秒"
    "  覆盖域名 : $($script:HostMap.Keys.Count)"
    "  候选来源 : $script:SourceInfo"
    foreach ($h in $script:HostMap.Keys) {
        '    {0,-38} {1}' -f $h, ($script:HostMap[$h] -join ', ')
    }

    ''
    '================== 2. 写入 hosts =================='
    try {
        $null = Save-HostsBlock -Lines $script:HostsLines
        $txt = [System.IO.File]::ReadAllText($tmpHosts)
        $ln = @($txt -split "`r`n")
        "  写入行数 : $($script:HostsLines.Count)"
        "  文件行数 : $($ln.Count)"
        "  含标记   : " + ($txt.Contains($MARK_START) -and $txt.Contains($MARK_END))
        "  备份生成 : " + (Test-Path $BACKUP_PATH)
    }
    catch {
        Write-CrashLog '端到端自检-写入' $_
        "  写入抛异常: $($_.Exception.Message)"
    }

    ''
    '================== 3. 闭环校验 =================='
    try {
        $vr = Repair-Hosts
        "  通过     : $($vr.Ok) / $($script:HostMap.Keys.Count)"
        "  未通过   : " + $(if ($vr.Fail.Count) { $vr.Fail -join ', ' } else { '无' })
        "  被轮换   : " + $(if ($vr.Rotated.Count) { $vr.Rotated -join ', ' } else { '无' })
        "  解析冲突 : " + $(if ($vr.Conflict.Count) { $vr.Conflict -join ', ' } else { '无' })
        if ($vr.Conflict.Count -gt 0) {
            '             （自检写的是临时 hosts，但解析读的仍是真实 hosts，此项仅供参考）'
        }
    }
    catch {
        Write-CrashLog '端到端自检-校验' $_
        "  校验抛异常: $($_.Exception.Message)"
    }

    ''
    '================== 4. 生成报告 =================='
    $rpt = ''
    try {
        $rpt = Save-Report -OutDir $env:TEMP
        if ($rpt -and (Test-Path $rpt)) {
            $rl = @(Get-Content $rpt -Encoding UTF8)
            "  文件     : $rpt"
            "  行数     : $($rl.Count)"
            "  前 3 行  : " + ($rl[0..2] -join ' | ')
        }
        else { '  生成失败' }
    }
    catch {
        Write-CrashLog '端到端自检-报告' $_
        "  报告抛异常: $($_.Exception.Message)"
    }

    ''
    '================== 5. 收尾 =================='
    $HOSTS_PATH  = $origHosts
    $BACKUP_PATH = $origBak
    foreach ($f in @($tmpHosts, ($tmpHosts + '.bak'), $rpt)) {
        if ($f -and (Test-Path $f)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    "  临时文件已清理"
    "  真实 hosts 未被改动: " + ([System.IO.File]::ReadAllText($origHosts).Contains($MARK_START))
    try { $form.Dispose() } catch { }
    exit 0
}

if ($SelfTest) {
    # 自检模式：创建完所有控件后立即退出，用于语法和运行时验证
    Write-Output 'SELFTEST OK'
    Write-Output ("控件数: {0}" -f $form.Controls.Count)
    Write-Output ("表格列数: {0}" -f $grid.Columns.Count)
    Write-Output ("候选池域名: {0}" -f $POOL.Keys.Count)
    $form.Dispose()
    exit 0
}

if ($TestRemote) {
    # 只验证远程补充这一环，不开界面
    $form.Dispose()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Get-RemotePool
    $sw.Stop()
    Write-Output ("耗时        : {0:N2} 秒" -f $sw.Elapsed.TotalSeconds)
    Write-Output ("可达源      : {0}/{1}" -f $r.SourceOk, $r.SourceTotal)
    Write-Output ("新增 IP 总数: {0}" -f $r.NewCount)
    Write-Output ("涉及域名    : {0}" -f $r.Added.Keys.Count)
    foreach ($h in $r.Added.Keys) {
        Write-Output ("  {0,-38} +{1}  {2}" -f $h, $r.Added[$h].Count, ($r.Added[$h] -join ', '))
    }
    exit 0
}

try {
    [void]$form.ShowDialog()
}
catch {
    Write-CrashLog '主窗体运行' $_
    try {
        [System.Windows.Forms.MessageBox]::Show(
            ("程序异常退出，已记录日志：`r`n" + $LOG_FILE + "`r`n`r`n" + $_.Exception.Message),
            'L1 GitHub Hosts', 'OK', 'Error') | Out-Null
    } catch { }
}
finally {
    try { $script:ToastTimer.Stop(); $script:ToastTimer.Dispose() } catch { }
    try { $form.Dispose() } catch { }
    # 正常退出要撤掉标记，否则下次启动会误报"上次异常退出"
    try { if (Test-Path $RUN_MARK) { Remove-Item $RUN_MARK -Force -ErrorAction SilentlyContinue } } catch { }
}
