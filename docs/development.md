# 开发记录：从 0 到 1.0.1

这份文档记录了这个工具怎么一步步变成现在的样子，包括**做过的判断、踩过的坑、以及为什么最后是这么设计的**。

写它的原因很简单：网上大部分 hosts 项目只有一份 README，看不到作者遇到过什么问题。而这个领域真正的难点全在细节里 —— 比如「为什么不能测 TCP 握手」这一条，就决定了整个工具的排序逻辑。

---

## 一、起点：先搞清楚竞品错在哪

一开始参考了这些项目：

| 项目 | 做法 |
|---|---|
| [GitHub520](https://github.com/521xueweihan/GitHub520) | DoH 拿 IP → GitHub Actions 测 TCP → 生成文本 |
| [ittuann/GitHub-IP-hosts](https://github.com/ittuann/GitHub-IP-hosts) | 2 路 DoH → 每周 CI 更新 |
| [Licoy/fetch-github-hosts](https://github.com/Licoy/fetch-github-hosts) | 客户端定时拉远程源 |
| [ineo6/hosts](https://github.com/ineo6/hosts) | 多源汇总 |
| [SwitchHosts](https://github.com/oldj/SwitchHosts) | 手动 / 订阅管理 hosts |
| [TinsFox/github-hosts](https://github.com/TinsFox/github-hosts) | Cloudflare Workers（已因 KV 配额被刷爆下线） |
| [maxiaof/github-hosts](https://github.com/maxiaof/github-hosts) | 手工维护 |

读完源码发现两个结构性问题：

**问题 1：测速位置不对。** GitHub520 的 `fetch_ips.py` 里有一行注释写得很直白：

```
GitHub runners are placed in Azure. Ping doesn't work in azure by design.
```

它们在 GitHub Actions 的机器上测速，测的是「Azure 机房 → GitHub」的延迟，和国内用户的宽带没有任何关系。

**问题 2：测速指标不对。** 所有项目都测 `socket.create_connection((ip, 443))`，也就是 TCP 握手。但国内这个握手会被中间设备代答 —— 实测所有 IP 的 TCP 握手都是 **1ms**，而从中国大陆到美国机房，光速往返的物理极限就要 100ms 以上。

1ms 是假的。真实延迟藏在后面的 TLS 握手阶段。

> 实测证据：`20.205.243.166` 的 TCP/TLS 握手只要 274ms，看起来很好，但 HTTP 请求发出去 6.7 秒拿不到任何响应。

结论：**要做就做本机实测，而且必须测到首字节。**

---

## 二、原型：命令行版（0.1 → 0.3）

第一版是 `GitHub-IP-Probe.ps1` + 一个 `.bat` 包装，纯命令行。

核心是一个裸 socket 测速函数：

```powershell
$tcp = New-Object System.Net.Sockets.TcpClient
$tcp.Connect($ip, 443)
$ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
$ssl.AuthenticateAsClient('github.com')   # 传域名才带正确的 SNI
```

一开始只测 TLS 握手，后来加了 TTFB（发出请求到收到首字节）。

**这一步犯的错：**

- 最初只测 TLS，结果把「握手 274ms 但发请求没响应」的 IP 排在第一位 → 改成测 TTFB
- 后来又发现只测 TTFB 会把握手慢的 IP 排前面（TLS 占总耗时一半以上）→ 改成 **TCP + TLS + TTFB 全链路**
- 最初「取最快一次」→ 会让偶尔成功一次的 IP 排名虚高 → 改成要求多次成功、取中位数

---

## 三、GUI 版：为什么最后是 WinForms（0.4 → 0.5）

命令行版对普通用户门槛太高（要开 PowerShell、改执行策略）。所以做了图形界面。

选项对比过：

| 方案 | 结论 |
|---|---|
| WinForms | 系统自带、零依赖、启动快 —— **选它** |
| WPF | 观感更好，但要重写全部布局，且无法在无界面环境验证 |
| Electron / WebView | 需要额外运行时，违背「单文件、免安装」 |

界面上刻意做了几个取舍：

- **不用图片资源**：图标是运行时用 GDI+ 画的（圆角矩形 + 白色 L），省掉一个文件
- **配色偏绿**：`#10B981` 主色，背景 `#F5F8F6`，表格斑马纹，避免「灰色老软件」的观感
- **提示用内联 Toast 而不是弹窗**：写入、保存这类非破坏性操作不该打断用户；只有「恢复初始」保留确认框

---

## 四、打包：单文件是怎么来的（0.5）

用户要求「双击就能用、不需要解压软件」，所以把 PowerShell 脚本内嵌进 `.bat`。

```
@echo off
set "SELF=%~f0"
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "...提取到 %TEMP% 并执行..."
exit /b
#PS-START
<# 完整脚本从这里开始 #>
```

运行逻辑：bat 读取自己 → 找到 `#PS-START` 标记 → 把后面的内容写到 `%TEMP%\L1GH_<随机>.ps1` → 隐藏窗口执行。

**踩的坑最多的一段**，见下一节。

---

## 五、踩坑记录（按发现顺序）

### 1. hosts 里的中文变成乱码

第一版往 hosts 写中文注释，结果记事本和 cmd 里全是问号 —— hosts 是 ANSI 编码，中文按 UTF-8 写进去就废了。

**解决**：hosts 内容全部改英文注释，只保留 IP + 域名。

### 2. bat 用 LF 换行，命令被截断

现象：报错 `'Hub-IP-GUI.ps1' 不是内部或外部命令`。

查字节发现 `40 65 63 68 6F 20 6F 66 66 **0A**` —— `0A` 是 LF。Windows cmd 需要 `0D 0A`，LF-only 会让 cmd 切错行，`set "GUI=...GitHub-IP-GUI.ps1"` 从中间断开。

**解决**：所有 bat 强制 CRLF。

### 3. 文件首字符莫名消失

现象：`@echo off` 变成 `echo off`，`<#` 变成 `#`，导致整个注释块被当命令执行，满屏 `无法将"GitHub"项识别为 cmdlet`。

查了很久，以为是写入工具的问题，真正原因是这一行：

```powershell
if ($text.StartsWith([char]0xFEFF)) { $text = $text.Substring(1) }
```

`[char]0xFEFF` 转成字符串是**空字符串**，而 `StartsWith("")` 永远返回 `true` —— 所以每次都会无条件砍掉第一个字符。

**解决**：改成用码点判断 `[int][char]$text[0] -eq 0xFEFF`。

### 4. 双击闪退（提权后文件被删）

现象：双击 → 黑框一闪 → 什么都没有。

原因链条：

```
① bat 把脚本提取到 %TEMP%\L1GH.ps1
② bat 启动它（非管理员）
③ 脚本检测到没权限 → 弹 UAC 开管理员进程 → 自己 exit
④ 原进程一退出，bat 立刻 del 掉临时文件
⑤ 管理员进程刚启动，文件已经没了 → 静默崩溃
```

**解决**：bat 不再删除临时文件。

### 5. PowerShell 变量名不区分大小写

`$Choice` 参数和内部 `$choice` 变量其实是同一个，导致命令行指定模式失效。

**解决**：改名。顺带发现 `$input` 是保留自动变量，也不能用。

### 6. 临时文件名固定导致第二次启动失败

测速时发现脚本执行期间会锁住自己的文件（读得到、写不进）。用固定名字 `%TEMP%\L1GH.ps1` 的话，**第二次双击会因为覆盖失败而毫无反应**。

**解决**：改成 `L1GH_<8位随机>.ps1`，每次唯一；启动时顺带清理 1 天前的旧文件。

### 7. `IndexOf('#PS-START')` 命中了错误的位置

打包脚本里用 `IndexOf('#PS-START')` 找正文起点，结果命中了**启动命令里**的 `'#PS-START'` 字符串（它就在第 3 行），导致正文从错误位置截断，提取出的脚本首字符变成 `'`。

**解决**：打包永远从 `src/GitHub-IP-GUI.ps1` 重建，不要在成品 bat 上做二次解析。

### 8. 用文本编辑器写的 .ps1 没有 BOM

在中文 Windows 上，PowerShell 5.1 读无 BOM 的 .ps1 会按 GBK 解码，中文全变乱码，报一堆语法错误。

**解决**：所有 .ps1 必须存成 UTF-8 **带 BOM**。

### 9. `[Math]::Min(1, 0.77)` 返回 1

屏幕适配做完后，小屏幕上完全不缩放。原因是 PowerShell 里 `880/880` 得到的是 **Int32** 的 `1`，`[Math]::Min` 于是选了 Int32 重载，把 `0.77` 四舍五入成 `1`。

**解决**：`[Math]::Min([double]$a, [double]$b)`。

### 10. 缩放按窗口尺寸算，边框差出十几像素

`Form.Width` 包含边框，但边框不参与缩放。小尺寸下内容会溢出客户区几个像素。

**解决**：按 `ClientSize` 计算缩放比，缩放后设置 `ClientSize` 而不是 `Size`。

---

## 六、成功率优化：从「能连上」到「真的能用」（0.8）

用户反馈「写入成功但有时候还是打不开」，于是做了一轮系统性测量。

### 测量 1：当前 hosts 的首条 IP 到底行不行

| 域名 | 首条 IP | 5 次成功 |
|---|---|---|
| **raw.githubusercontent.com** | 185.199.110.133 | **2/5** |
| github.com | 20.27.177.113 | 4/5 |
| avatars.githubusercontent.com | 185.199.110.133 | 3/5 |
| 其余 6 个 | — | 5/5 |

结论：**写进去的 IP 会随着时间变坏，而工具写完就不管了。**

### 测量 2：失败发生在哪一层

36 次完整请求：

| 阶段 | 次数 | 占比 |
|---|---|---|
| 成功 | 26 | 72% |
| TCP 连接超时 | 6 | 17% |
| TLS 握手失败 | 4 | 11% |
| HTTP 层异常 | **0** | **0%** |

两个结论：
- HTTP 层校验没必要做，TLS 能握手成功就说明对面是真 GitHub
- 失败是**连接级随机中断**，重试和换 IP 是对的方向

### 测量 3：并发是不是元凶

并发 4 和并发 16 的总成功率完全一样（都是 70%），说明不是工具自己把对面打挂了。

### 对应的四项改动

1. **每域名写 4 个 IP**：单次成功率 70% → 写 2 个全挂 9%，写 4 个 0.8%
2. **粗筛失败补测一次**：长超时再给一次机会，避免被随机丢包误杀
3. **写入后闭环校验**：按系统实际解析结果验一遍，不通就换下一个重写
4. **补 `camo.githubusercontent.com`**：README 图片实际走这个域名，不是 raw

### 踩的坑：单次失败就轮换是错的

第一版校验是「失败一次就换 IP」，结果把好 IP 换掉了 —— 30% 是随机丢包，重试同一个 IP 往往就通了。

**解决**：同一个 IP 先重试一次，两次都失败才轮换。

---

## 七、排序口径与网段分散（0.9）

### 全链路计时

把 11 个 IP 各测 4 次，把三段分开计时：

| IP | TLS 握手 | 全链路 |
|---|---|---|
| 20.27.177.113 | 490 ms | **719 ms** |
| 140.82.114.5 | 466 ms | 947 ms |
| 140.82.113.11 | 552 ms | 1032 ms |
| **140.82.112.9** | **1264 ms** | **1736 ms** |
| 20.205.243.166 | 417 ms | 2164 ms |

`140.82.112.9` 的 TLS 要 1264ms，但 TTFB 很低 —— 只测 TTFB 会把它排进前列，用户实际要等 1.7 秒。

**改动**：排序改用全链路，取中位数。

### 网段分散

同一个 /24 的路由是同一条，4 个 IP 全落在一个段里等于没有冗余。

**改动**：第 1 名取最快的，第 2-4 名优先选不同 /24 的，凑不齐再按原序补。

---

## 八、稳定性与兼容性（1.0）

### 全局异常兜底

原来没有任何兜底，任何未捕获异常都会弹 .NET 的「未处理的异常」框，用户除了关掉没别的选择。

**改动**：
- `Application.add_ThreadException` + `AppDomain.add_UnhandledException`
- 崩溃日志写 `%LOCALAPPDATA%\L1GitHubHosts\error.log`
- 主窗体 try/finally

验证方式很土但有效：起一个窗体，用 Timer 抛一个异常，看日志有没有落盘、窗口有没有崩。

### TLS 1.2

Windows 7/8 的 .NET 默认只协商到 TLS 1.0，而 GitHub 早已只收 1.2+。不显式指定的话，旧系统上表现为「所有 IP 都连不上」，报错完全看不出原因。

**改动**：`ServicePointManager.SecurityProtocol` + 每个 SslStream 显式传协议（runspace 内不共享脚本作用域，所以每处都要写）。

### PS 版本闸门

Win7 自带 PowerShell 2.0，而脚本用了 `[ordered]@{}`、`Get-CimInstance` 等 3.0+ 语法，直接跑就是满屏语法错误。

**改动**：启动先检查版本，不够就弹中文提示再退出。

---

## 九、边界压测（1.0）

做了 `-StressTest` 开关，9 个场景全部走真实代码路径（hosts 指向临时文件）：

| 场景 | 结果 |
|---|---|
| 断网 / 候选全部失败 | PASS，返回 0 条不崩 |
| hosts 正常写入 | PASS |
| hosts 被其它程序独占 | PASS，正确抛异常 |
| hosts 只读 | PASS，正确抛异常 |
| 空候选写 hosts | PASS，返回 0 行 |
| IP 选择边界（0/1/2/5 个候选） | PASS |
| 崩溃日志写入 | PASS |
| 空结果保存报告 | PASS |
| 目标目录不可写 | PASS，返回空并提示 |

---

## 十、全流程自检（1.0.1）

加了 `-DryRun`：完整跑「测速 → 写 hosts → 校验 → 出报告」，但 hosts 指向临时文件。

跑完发现 4 个 bug：

1. **报告文件名只到分钟** → 同一分钟保存两次互相覆盖，改成精确到秒
2. **校验期间可以再点测速** → 两边同时改写 hosts，加 `Verifying` 守卫
3. **校验抛异常被报成「写入失败」** → hosts 其实已写入，拆成独立 try
4. **新测速后「打开报告」还是旧文件** → 测速开始时作废

---

## 十一、现状与后续

当前版本 1.0.1，10 个域名、60+ 候选 IP、完整链路约 15 秒。

**已知局限（诚实说明）：**

- **只有 Windows**：Mac / Linux 用户用不了
- **无法保证 100% 可用**：hosts 是静态映射，网络是动态环境。工具能做到的是「每次跑都重新选最合适的」，做不到「一直有效」
- **`gist.github.com` 这类域名无解**：DNS 被投毒，换 IP 也连不上，需要代理
- **IPv6 未覆盖**：hosts 只写 IPv4。如果系统启用了 IPv6，`raw` 和 `githubassets` 这些有 AAAA 记录的域名可能优先走 IPv6，绕过 hosts

**可能的方向：**

- 定时任务（`-InstallTask` 思路已实现但未接入）
- 跨平台 bash 版
- 更多域名覆盖（目前刻意只保留 10 个，因为实测其余域名光靠 DNS 就够用）

---

## 十二、网站与发布（1.0.1 之后）

工具本身到 1.0.1 就稳定了，后面全部是「怎么让别人拿到、看懂、查得到」的工作。

### 仓库结构

```
README.md                 用法、两种方式对比、FAQ、竞品对比、文档索引
CHANGELOG.md              版本记录（只跟 .bat 版本号走）
docs/index.html           宣传页（GitHub Pages，源在 docs/）
docs/development.md       就是本文
docs/hosts.txt            在线列表快照，Actions 定时刷新
docs/setup-workflow.md    Actions 配置说明
scripts/build.ps1         ★ 从 src 打包出 dist
scripts/gen_hosts.py      生成 hosts.txt
src/GitHub-IP-GUI.ps1     全部源码，单文件
dist/L1-GitHub-Hosts.bat  构建产物（Release 资产就是它）
```

### 站点是怎么来的

`docs/` 直接作为 Pages 根目录，没有构建步骤，改完 HTML 推上去就是新的。

页面本身不依赖仓库快照：打开时实时向 jsDelivr、gitcdn、本地快照三个源拉数据，前端按「实测延迟分层 → 多源共识」排序渲染。所以就算快照过期，表格也是新的。

「方法二」的复制和下载都是浏览器端现生成的，不读仓库文件 —— 这样文件头的时间永远等于你点下去的那一刻。

### 三个 CSS bug（都是「看起来对，跑起来不对」）

**① `.wrap` 吃掉了区块的上下内边距**

```css
.wrap{max-width:1040px;padding:0 20px}     /* 类选择器 */
section{padding:44px 0}                     /* 元素选择器，被上面覆盖 */
```

`.wrap` 优先级更高，于是 `padding-top/bottom` 全变成 0，整页标题都贴着上一块内容。改成 `section.wrap{padding-top:44px;padding-bottom:44px}` 才正常。

**② 对比表的 `min-width` 把整页撑宽**

窄屏下表格 `min-width:600px` 没有容器约束，直接把 body 撑成 600px 宽，整页都溢出。加一层 `.tblwrap{overflow-x:auto}` 让表格自己滚。

**③ 复制提示的伪元素占位**

```css
code.cp::after{content:"复制";opacity:0}   /* 看不见，但仍然占布局 */
```

长 URL 占满一行后，这个隐形的「复制」被挤到下一行，露出一个空白的边框块。改成 `display:none`，hover 时才 `display:inline`。

### 无头浏览器验证的坑

用 `msedge --headless=new --screenshot --window-size=390,900` 截窄屏，会看到文字被右侧裁掉，很容易误判成「页面横向溢出」。

真相：**headless 的最小视口是 477px**，传 320 / 360 / 390 都按 477 渲染，但截图按传入值裁切。

判断是否真溢出不能靠看截图，要注入脚本读 `document.documentElement.scrollWidth`，再用 `--dump-dom` 把结果读出来比对。

### Actions 的 cron 不会准点跑

工作流状态是 `active`，但 `17 * * * *` 整整两小时一次都没触发，`hosts.txt` 停在旧时间。

- 低活跃仓库的 schedule 会被延迟甚至跳过，不能假设它按点执行
- 改成 `7,37 * * * *`（每 30 分钟）提高命中率，并保留 `workflow_dispatch` 手动兜底
- 实测仍然很稀疏：建库头两天只有 2 次定时运行（UTC `00:36`、`19:39`，间隔 4.9 小时），而计划是每 30 分钟
- 更重要的是：**页面不要依赖定时产物**。下载已改成前端即时生成

另外两个 Actions 相关的坑：

- 提交 `.github/workflows/*` 的令牌必须额外有 `workflow` 权限，否则返回 404
- 连续两次推送会让 Pages 构建 race，先提交的那次 `errored`；调 `POST /repos/{owner}/{repo}/pages/builds` 可以手动重建

### 下载链接的取舍

| 位置 | 指向 | 理由 |
|---|---|---|
| 方法一卡片按钮 | `releases/download/v1.0.1/L1-GitHub-Hosts.bat` | 一次点击直接下载 |
| 页脚「下载」 | `releases/latest` | 想看版本说明的人在这里 |

直链会 302 跳到 `release-assets.githubusercontent.com`，`Content-Type: application/octet-stream`，浏览器直接存盘。取前 3 字节确认是 `40 65 63`（`@ec`），说明拿到的是真文件而不是 HTML 错误页。

### 协作纪律：先 diff 再推

这个仓库会有人在网页上直接改（改标题文案、加粗某个词）。**脚本推送前必须先拉远程做 diff**，否则会静默覆盖。

做法：取远程文件 → base64 解码落盘 → `diff -u` 对比 → 再决定推什么。提交时把远程返回的 `sha` 带上，GitHub 会用乐观锁挡住「基于旧版本覆盖」的写入。

### 在新机器上继续开发

```
git clone https://github.com/gooooddayy/L1-github-hosts.git
cd L1-github-hosts
```

1. 改 `src/GitHub-IP-GUI.ps1`（唯一源文件）
2. 打包 —— 会先跑一次界面自检，不通过不会产出：

```
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

3. 六个启动开关（前四个是自检，后两个是排障）：

```
-SelfTest     界面能否创建（控件 / 列 / 域名数）
-StressTest   边界 9 项（断网、只读、占用、空结果…）
-DryRun       端到端：测速 → 写 hosts → 校验 → 报告，hosts 指向临时文件
-TestRemote   三个远程源连通性
-Diagnose     打印环境：PS 版本 / 管理员权限 / WinForms 与 Drawing 能否加载
-NoRemote     只用内置候选池，不拉三个远程源
```

4. 产物覆盖 `dist/L1-GitHub-Hosts.bat`，和源码一起提交

**注意**：永远从 `src` 重建，不要在成品 `.bat` 上二次解析 —— 启动命令里本身就含 `#PS-START` 这个字符串，用 `IndexOf` 找正文会命中错误位置（见第五章第 7 条）。

实测过：在只有仓库文件、没有 `dist` 产物的干净目录里跑 `build.ps1`，生成的文件与仓库里那份 **SHA256 完全相同**。所以换电脑不需要带任何本地文件。

唯一会变的是 `docs/hosts.txt` —— 它由 Actions 定时覆盖（计划每 30 分钟，实际被 GitHub 限流，见上一节实测数据），本地版本落后是正常的。

