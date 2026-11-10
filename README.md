# L1 GitHub Hosts

> **更新 GitHub 最新 hosts · GitHub 访问加速 · 本机实测可用 IP**
>
> 解决 `github.com` 打不开、转圈、README 图片无法显示、`raw.githubusercontent.com` 加载失败。

**[⬇ 下载 Windows 版](https://github.com/gooooddayy/L1-github-hosts/releases/latest)** ·
**[🌐 在线实时 IP 列表](https://gooooddayy.github.io/L1-github-hosts/)** ·
**[📖 使用说明](#快速开始3-步)**

---

## 这是什么

一个 Windows 上的小工具，解决「GitHub 打不开、图片裂开、加载特别慢」的问题。

双击运行 → 在你自己的网络上实测每个候选 IP 的完整访问链路 → 挑出真正能用的写入 `hosts` → 写完再验证一遍，不通就自动换下一个。

和网上那些「复制一份 hosts 粘贴进去」的项目相比，最大的区别是：**它不用别人的测速结果，只在自己机器上测。**

---

## 为什么它比直接抄一份 hosts 更靠谱

GitHub 在国内访问不稳，绝大多数人的做法是找一份别人维护好的 hosts 文件粘进系统。问题在于：

| 别人的 hosts 文件 | 这个工具 |
|---|---|
| IP 是维护者在**他自己网络**上测的 | 在**你的网络**上现测 |
| 测完生成静态文本，不会再变 | 每次运行**重新测** |
| 测速指标是 TCP 握手（国内常被中间设备代答，1ms 是假值） | 测 **TCP + TLS + 首字节**完整链路 |
| 一个域名给 1 个 IP，挂了就挂 | 给 **4 个不同网段**的 IP，同时失效概率 0.8% |
| 写完就结束，不知道有没有生效 | 写完后**逐个域名闭环验证**，不通自动换 |

具体到数字：实测同一批 IP，TLS 握手耗时从 450ms 到 1264ms 不等，**光看 TCP 握手完全分不出来**。而握手占总耗时的一半以上，只测首字节会把最慢的 IP 排到前面。

---

## 快速开始（3 步）

### 1. 下载

到 [Releases](https://github.com/gooooddayy/L1-github-hosts/releases/latest) 下载 `L1-GitHub-Hosts.bat`。

> 只有一个文件，不需要安装，不需要解压，不依赖 .NET 以外的任何运行库。

**如果 Windows 提示「此文件来自其他计算机」**：右键文件 → 属性 → 勾选底部的「解除锁定」→ 确定。这是 Windows 对下载文件的默认保护，任何未签名程序都会遇到。

### 2. 双击，点「是」

会弹一次 UAC 提权窗口 —— 因为要修改 `C:\Windows\System32\drivers\etc\hosts`，这个文件必须管理员权限才能写。

点「是」之后界面就出来了，点 **开始测速**，等 15～25 秒。

### 3. 写入并校验

点 **写入 hosts**。工具会：

1. 备份原文件到 `hosts.bak`
2. 写入测出来的 IP（每个域名 4 个，来自不同网段）
3. 刷新 DNS 缓存
4. **逐个域名验证真的能通**，不通就自动换下一个 IP 重写

看到右上角提示「已写入并校验通过（10/10 个域名）」，就可以打开浏览器试了。

---

## 浏览器 DNS 缓存：最后一步，很多人卡在这

系统 DNS 刷新了，但 **浏览器有自己的 DNS 缓存**，不清的话还是走旧 IP。

**Chrome / Edge** —— 地址栏粘贴下面这行，回车后点 **Clear host cache**

```
chrome://net-internals/#dns
```

**Firefox** —— 地址栏粘贴下面这行，回车后点 **Clear DNS Cache**

```
about:networking#dns
```

**系统级** —— `Win + R` 输入 `cmd` 回车，再粘贴下面这行

```
ipconfig /flushdns
```

> ⚠️ `chrome://` 和 `about:` 这类内部页面**不允许网页直接跳转**（浏览器安全限制），所以在线页面上的按钮是「复制链接」，粘到地址栏回车即可。

最简单粗暴的办法：**把浏览器完全关掉再打开**，缓存自然就没了。

---

## 实时 hosts 列表

**[→ 打开在线实时列表](https://gooooddayy.github.io/L1-github-hosts/)**

页面会实时拉取多个公开源，按「被几个源同时认可」排序展示，同时给出可直接复制的 hosts 片段：

```
https://gooooddayy.github.io/L1-github-hosts/hosts.txt
```

> **注意**：在线列表是**多源交叉验证**的结果（几个独立项目都给出同一个 IP，说明它更可能稳定），**不是**在你机器上实测的。
>
> 想要真正适合你自己线路的结果，请用桌面版工具——那才是本机实测。

<sub>仓库里的 `hosts.txt` 由 GitHub Actions 每小时自动刷新，原理与排序规则见 [docs/setup-workflow.md](docs/setup-workflow.md)。</sub>

---

## 常见问题

<details>
<summary><b>换了 hosts 还是打不开，为什么？</b></summary>

按可能性排序：

1. **浏览器缓存没清** —— 见上面那一节，最常见
2. **hosts 里有重复条目** —— 别的工具写过同一域名，排在前面抢走解析。点工具里的「恢复初始」清干净再写入
3. **IP 已经失效** —— hosts 是静态快照，IP 会随 GitHub 的调度变化。重新跑一次工具
4. **网络环境变了** —— 换了 WiFi、开了代理、运营商调整，都会让旧结果失效
5. **域名本身被污染** —— 例如 `gist.github.com`，DNS 解析结果完全不是 GitHub 的 IP，这类域名 hosts 解决不了

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

这不是工具不稳定，是它如实反映了你当前network的状况。也正因如此，**不建议长期沿用一份旧的 hosts**。

</details>

<details>
<summary><b>支持 Windows 7 吗？</b></summary>

需要 **PowerShell 3.0 以上**。Windows 7 自带的是 2.0，请先安装 [WMF 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616)。

工具在启动时会检查版本，不够会弹出中文提示，不会出现一堆看不懂的报错。

</details>

<details>
<summary><b>360 / 火绒 报毒怎么办？</b></summary>

工具是纯文本的 `.bat` + PowerShell 脚本，没有任何二进制文件，源码在 [`src/`](src/) 里可以直接看。

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

- 单文件 `.bat`，内嵌完整 PowerShell 脚本，解压到 `%TEMP%` 后运行
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
