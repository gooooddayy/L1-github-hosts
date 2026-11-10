# L1 GitHub Hosts

> **更新 GitHub 最新 hosts · GitHub 访问加速 · Windows 单文件 .bat**
>
> 解决 `github.com` 打不开、转圈、README 图片无法显示、`raw.githubusercontent.com` 加载失败。

**[⬇ 下载 Windows 版（.bat 单文件）](https://github.com/gooooddayy/L1-github-hosts/releases/latest)** ·
**[🌐 在线实时 hosts 列表](https://gooooddayy.github.io/L1-github-hosts/)** ·
**[📖 使用步骤](#方法一使用步骤4-步)**

---

## 先选一种用法

| | **方法一 · bat工具**（推荐） | **方法二 · 实时列表** |
|---|---|---|
| 怎么用 | 下载一个 `.bat` 文件，双击运行 | 打开网页，复制或下载现成内容 |
| 测速位置 | **你自己的电脑**，走你的宽带 | 第三方项目的机器 |
| 成功率 | **高**：本机实测 + 写入后逐个域名校验，不通自动换 IP | 中：取决于源站数据和你线路是否匹配 |
| 每域名 IP 数 | **4 个**，尽量来自不同网段 | 4 个，按共识与延迟分层 |
| 需要什么 | 管理员权限（一次 UAC） | 无 |
| 数据新鲜度 | 每次运行都是当次实测 | 源站与快照定时刷新，可能滞后几十分钟 |
| 适合 | 长期使用 | 临时应急、不想运行程序、Win / Mac / Linux |

> **两种不要同时用。** 各自有独立的起止标记，同时存在会让同一域名有多条记录、互相抢优先级。

---

## 写入 hosts（4 步）

Windows 版就是**一个 `.bat` 文件**，不是安装包，不用解压，不用装任何运行库。

### 1. 下载 `L1-GitHub-Hosts.bat`

打开 [Releases](https://github.com/gooooddayy/L1-github-hosts/releases/latest)，下载 `L1-GitHub-Hosts.bat`。

> **提示「此文件来自其他计算机」怎么办**：右键文件 → 属性 → 勾选底部「解除锁定」→ 确定。这是 Windows 对下载文件的保护，任何未签名程序都会遇到。

### 2. 双击运行，UAC 点「是」

因为要写 `C:\Windows\System32\drivers\etc\hosts`，这个文件必须管理员权限。只会弹这一次。界面出来后点 **开始测速**，等 15～25 秒。

### 3. 点「写入 hosts」

工具会依次做：备份原文件 → 写入测出的 IP（每域名 4 个）→ 刷新系统 DNS → **逐个域名验证真的能通**，不通就把下一个 IP 换上来重写。

右上角提示「已写入并校验通过（10/10 个域名）」即成功。

### 4. 刷新本地 DNS（必做）

见下一节。

---

## 刷新 DNS

hosts 改完，系统里还缓存着旧的解析结果。先刷新本地 DNS，再看浏览器那一层。

**① 本地 DNS（必做）** —— `Win + R` → 输入 `cmd` → 回车，粘贴：

```
ipconfig /flushdns
```

看到「已成功刷新 DNS 解析缓存」就完成了。

**② 浏览器自己的缓存（打不开时再清）**

| 浏览器 | 地址栏粘贴 | 然后点 |
|---|---|---|
| Chrome / Edge | `chrome://net-internals/#dns` | **Clear host cache** |
| Firefox | `about:networking#dns` | **Clear DNS Cache** |

> 网页不能直接跳转到 `chrome://`、`about:` 这类浏览器内部页（安全限制），在线页面上只提供**复制按钮**，粘到地址栏回车即可。最省事的办法其实是把浏览器完全关掉再打开。

---

## 方法二：实时 hosts 列表

**[→ 打开在线列表](https://gooooddayy.github.io/L1-github-hosts/)**

要粘贴的目标文件：

```
C:\Windows\System32\drivers\etc\hosts
```

页面上的「方法二」卡片里点「打开列表 / 复制 / 下载」，会弹出窗口显示：

- 每个域名推荐 4 个 IP，按「实测延迟分层 → 多源共识」排序
- 数据更新时间 + 本次读取时间
- **一键复制全部**（自动带好起止标记，粘到 hosts 末尾即可，不会叠加第二份）
- 下载 `hosts.txt`

快照直链（可直接下载或订阅）：

```
https://gooooddayy.github.io/L1-github-hosts/hosts.txt
```

> **注意**：在线列表是**多源交叉验证**的结果（几个独立项目都给出同一个 IP，说明它更可能稳定），**不是**在你机器上实测的。想要最适合自己线路的结果，用方法一。
>
> 仓库里的 `hosts.txt` 由 GitHub Actions 每小时自动刷新，原理与排序规则见 [docs/setup-workflow.md](docs/setup-workflow.md)。

---

## 为什么它比直接抄一份 hosts 更靠谱

| 别人的 hosts 文件 | 这个工具 |
|---|---|
| IP 是维护者在**他自己网络**上测的 | 在**你的网络**上现测 |
| 测完生成静态文本，不会再变 | 每次运行**重新测** |
| 测速指标是 TCP 握手（国内常被中间设备代答，1ms 是假值） | 测 **TCP + TLS + 首字节**完整链路 |
| 一个域名给 1 个 IP，挂了就挂 | 给 **4 个不同网段**的 IP，同时失效概率 0.8% |
| 写完就结束，不知道有没有生效 | 写完后**逐个域名闭环验证**，不通自动换 |

具体到数字：实测同一批 IP，TLS 握手耗时从 450ms 到 1264ms 不等，**光看 TCP 握手完全分不出来**。而握手占总耗时的一半以上，只测首字节会把最慢的 IP 排到前面。

---

## 常见问题

<details>
<summary><b>换了 hosts 还是打不开，为什么？</b></summary>

按可能性排序：

1. **本地 DNS 没刷新** —— 命令行执行 `ipconfig /flushdns`
2. **浏览器缓存没清** —— 见上面那一节，或把浏览器完全关掉重开
3. **hosts 里有重复条目** —— 别的工具写过同一域名，排在前面抢走解析。点工具里的「恢复初始」清干净再写入
4. **IP 已经失效** —— hosts 是静态快照，IP 会随 GitHub 的调度变化。重新跑一次工具
5. **域名本身被污染** —— 例如 `gist.github.com`，DNS 解析结果完全不是 GitHub 的 IP，这类域名 hosts 解决不了

</details>

<details>
<summary><b>两种方法可以一起用吗？</b></summary>

不要。方法二复制的内容自带独立的起止标记，和方法一写的那段是两套，同时存在会让同一个域名有多条记录、互相抢优先级。

选一种就好。切换前把另一套删掉，或点工具里的「恢复初始」。

</details>

<details>
<summary><b>为什么每个域名要写 4 个 IP？</b></summary>

实测这条线路单次 TLS 连接的成功率约 **70%**，失败是随机的（不是慢，是连接被中断）。

- 写 2 个 IP，全部失败的概率是 **9%**
- 写 4 个，降到 **0.8%**

Windows 按 hosts 文件顺序返回地址，Chrome 和 curl 在首个地址连不上时会自动尝试下一个。

而且这 4 个 IP 会**尽量来自不同网段**——同一个 /24 的路由是同一条，全写一个段里等于没有备份。

</details>

<details>
<summary><b>会不会影响别的网站？</b></summary>

不会。工具只写 `# === GitHub IP BEGIN ===` 到 `# === GitHub IP END ===` 之间的内容，其它行一律不碰。

写入前会把原文件备份成 `hosts.bak`，点「恢复初始」可以把整个文件还原成 Windows 默认状态。

</details>

<details>
<summary><b>为什么每次运行结果都不一样？</b></summary>

因为网络本身在变。同一个 IP，我实测过两次间隔两分钟，TLS 握手从 447ms 变成 2424ms。

这不是工具不稳定，是它如实反映了你当前网络的状况。也正因如此，**不建议长期沿用一份旧的 hosts**。

</details>

<details>
<summary><b>支持 Windows 7 吗？</b></summary>

需要 **PowerShell 3.0 以上**。Windows 7 自带的是 2.0，请先安装 [WMF 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616)。

工具在启动时会检查版本，不够会弹出中文提示，不会出现一堆看不懂的报错。

</details>

<details>
<summary><b>360 / 火绒 报毒怎么办？</b></summary>

工具是纯文本的 `.bat`，里面内嵌的是 PowerShell 脚本，没有任何二进制文件，源码在 [`src/`](src/) 里可以直接看。

但「修改 hosts」是杀毒软件的重点监控行为，可能被拦截。如果写入失败，日志里会明确告诉你是「没有权限」还是「文件被占用」。临时退出安全软件再写入即可。

</details>

---

## 和其它 GitHub hosts 项目的对比

| 项目 | 数据来源 | 测速指标 | 测速位置 | 写入后校验 |
|---|---|---|---|---|
| **L1 GitHub Hosts** | 内置池 + 3 个公开源 | **TCP+TLS+首字节** | **本机** | **有，自动换 IP** |
| GitHub520 | DoH + 多个 DNS | TCP 握手 | GitHub Actions | 无 |
| ittuann/GitHub-IP-hosts | 2 路 DoH | TCP 握手 | GitHub Actions | 无 |
| Licoy/fetch-github-hosts | 同步远程源 | 无 | — | 无 |
| ineo6/hosts | 多源 | 无 | — | 无 |
| SwitchHosts | 手动 / 订阅 | 无 | — | 无 |

TCP 握手在国内会被中间设备代答，测出来常常是 1ms 的假值 —— 这就是为什么很多 hosts 项目挑出来的「最快 IP」你用起来并不快。

---

## 技术细节

- 单文件 `.bat`，内嵌完整 PowerShell 脚本，运行时释放到 `%TEMP%` 再执行
- 界面用 WinForms，不依赖任何第三方组件
- 测速用裸 socket + SslStream，**不走系统代理**，测的是真实路径
- 强制 TLS 1.2+，兼容 Windows 7/8 的旧版 .NET
- 崩溃日志写到 `%LOCALAPPDATA%\L1GitHubHosts\error.log`
- 高 DPI 和小屏幕自动缩放，1366×768 @125% 也能完整显示

**自检命令**（源码位于 [`src/GitHub-IP-GUI.ps1`](src/GitHub-IP-GUI.ps1)）：

```powershell
powershell -ExecutionPolicy Bypass -File .\src\GitHub-IP-GUI.ps1 -SelfTest    # 界面自检
powershell -ExecutionPolicy Bypass -File .\src\GitHub-IP-GUI.ps1 -StressTest  # 边界压测（9 项）
powershell -ExecutionPolicy Bypass -File .\src\GitHub-IP-GUI.ps1 -DryRun      # 端到端全流程
powershell -ExecutionPolicy Bypass -File .\src\GitHub-IP-GUI.ps1 -TestRemote  # 远程源连通性
```

---

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)，开发过程中的问题与解决方案见 [docs/development.md](docs/development.md)。

---

## 相关关键词

GitHub 访问加速 · 更新 GitHub 最新 hosts · GitHub 打不开怎么办 · 解决 GitHub 图片无法显示 · 加速 GitHub 网页浏览 · github.com 加载慢 · raw.githubusercontent.com 加速 · GitHub hosts 2026 · hosts 一键写入 · Windows hosts 工具 · DNS 刷新 · ipconfig flushdns

## License

[MIT](LICENSE) — 随便用，出问题别找我。
