<#
    从 src/GitHub-IP-GUI.ps1 打包出 dist/L1-GitHub-Hosts.bat（单文件版）

    用法：powershell -ExecutionPolicy Bypass -File scripts/build.ps1

    注意：永远从 src 重建，不要在成品 bat 上做二次解析 ——
    启动命令里本身就含有 '#PS-START' 这个字符串，用 IndexOf 找正文会命中错误位置。
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root 'src\GitHub-IP-GUI.ps1'
$out  = Join-Path $root 'dist\L1-GitHub-Hosts.bat'

if (-not (Test-Path $src)) { throw "找不到源码：$src" }

$body = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
if ($body.Length -gt 0 -and [int][char]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }
$body = $body -replace "`r`n", "`n" -replace "`n", "`r`n"

# bat 头必须是纯 ASCII + CRLF，否则 cmd 会切错行、中文会变问号
$PC = [char]37      # %
$Q  = [char]39      # '

$cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' +
       '$p=' + $Q + '{P}SELF{P}' + $Q + ';' +
       'Get-ChildItem $env:TEMP -Filter ' + $Q + 'L1GH_*.ps1' + $Q + ' -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime -lt (Get-Date).AddDays(-1)}|Remove-Item -Force -ErrorAction SilentlyContinue;' +
       '$o=Join-Path $env:TEMP (' + $Q + 'L1GH_' + $Q + '+[guid]::NewGuid().ToString(' + $Q + 'N' + $Q + ').Substring(0,8)+' + $Q + '.ps1' + $Q + ');' +
       '$l=@(Get-Content -LiteralPath $p -Encoding UTF8);' +
       '$i=-1;for($k=0;$k -lt $l.Count;$k++){if($l[$k].Trim() -eq ' + $Q + '#PS-START' + $Q + '){$i=$k;break}};' +
       'if($i -lt 0){exit 2};' +
       '$l[($i+1)..($l.Count-1)]|Set-Content -LiteralPath $o -Encoding UTF8;& $o"'

$header = @()
$header += '@echo off'
$header += 'set "SELF={P}~f0"'
# 用 /min 而不是 /b：/b 会跟调用者的控制台共用窗口，脚本再隐藏就会把用户自己的终端也藏掉
$header += 'start "" /min ' + $cmd
$header += 'exit /b'
$header += '#PS-START'
$head = (($header -join "`r`n") + "`r`n").Replace('{P}', $PC)

$dir = Split-Path -Parent $out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($out, ($head + $body), (New-Object System.Text.UTF8Encoding($false)))

# 自检：提取回来跑一遍界面自检
$lines = @(Get-Content -LiteralPath $out -Encoding UTF8)
$idx = -1
for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim() -eq '#PS-START') { $idx = $k; break } }
if ($idx -lt 0) { throw '打包失败：找不到 #PS-START 标记' }

$tmp = Join-Path $env:TEMP 'L1GH_buildcheck.ps1'
$lines[($idx + 1)..($lines.Count - 1)] | Set-Content -LiteralPath $tmp -Encoding UTF8
$first = ([System.IO.File]::ReadAllBytes($tmp))[3]
if ($first -ne 0x3C) { throw ("打包失败：提取出的脚本首字符是 0x{0:X2}，应为 0x3C" -f $first) }

$size = [math]::Round((Get-Item $out).Length / 1024, 1)
& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -SelfTest
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host ("打包完成：{0} （{1} KB）" -f $out, $size) -ForegroundColor Green
