# hosts.txt 自动刷新

仓库里的 `docs/hosts.txt` 是网站「下载 hosts.txt」的数据源，**目前由 `.github/workflows/update-hosts.yml` 每小时自动刷新**（每小时第 17 分钟）。

页面本身不依赖这个快照 —— 打开页面时会直接向 2 个公开源实时拉取。快照的作用是兜底（源站全部不可达时）和提供可下载的文件。

## 验证是否在跑

1. 打开仓库的 **Actions** 标签页
2. 左侧选 **Update hosts**
3. 应该能看到每次运行记录；点 **Run workflow** 可以手动触发一次
4. 跑完后 `docs/hosts.txt` 开头的「更新时间」会变

## 如果哪天失效了

工作流需要令牌具备 `workflow` 权限才能创建。如果你重新初始化了仓库，按下面的方式加回去即可。

### 方式一：用带 `workflow` 权限的令牌（一步到位）

令牌需要同时勾选 **`repo`** 和 **`workflow`** 两个权限。

### 方式二：网页上手动添加（不需要任何权限）

1. 打开仓库首页
2. 点 **Add file → Create new file**
3. 文件名填：`.github/workflows/update-hosts.yml`
4. 粘贴下面全部内容
5. 底部选 **Commit directly to the `main` branch** → Commit

```yaml
name: Update hosts

on:
  schedule:
    # 每小时第 17 分钟跑一次（避开整点的 CI 高峰）
    - cron: '17 * * * *'
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'scripts/gen_hosts.py'
      - '.github/workflows/update-hosts.yml'

permissions:
  contents: write

concurrency:
  group: update-hosts
  cancel-in-progress: true

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Generate docs/hosts.txt
        run: python scripts/gen_hosts.py

      - name: Commit if changed
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          if git diff --quiet -- docs/hosts.txt; then
            echo "hosts.txt 无变化，跳过提交"
          else
            git add docs/hosts.txt
            git commit -m "chore: refresh hosts.txt [skip ci]"
            git push
          fi
```

---

## 验证是否生效

1. 打开仓库的 **Actions** 标签页
2. 左侧应该出现 **Update hosts**
3. 点进去 → **Run workflow** 手动触发一次
4. 跑完后 `docs/hosts.txt` 里的「更新时间」应该变成当前时间

## 它做什么

`scripts/gen_hosts.py` 会：

1. 拉取 3 个公开源（GitHub520 / ittuann / Licoy）
2. 按「同一 IP 被几个源同时给出」计票
3. **先按实测延迟分层过滤**（`20.205.243.x` 这类偏慢的排后面），同层内再按票数
4. 每个域名取前 4 个，写入 `docs/hosts.txt`
5. 内容没变则不提交，避免刷屏

## 为什么排序要加「实测分层」

多源共识只说明「这个 IP 存在且被多个项目认可」，**不说明它在国内快**。

典型例子：`20.205.243.166` 三个源都推荐，但实测全链路 2164ms，是最慢的一档；而 `140.82.114.x` 只有两个源给，实测 975ms。

所以脚本里有一张 `TIER` 表，来自 2026-11 在中国大陆线路上的实测数据：

| 网段 | 全链路均值 | 层级 |
|---|---|---|
| 20.27.177.x | 719 ms | 1 |
| 140.82.114.x / 185.199.x | 975 ms | 2 |
| 140.82.113.x | 1173 ms | 3 |
| 140.82.112.x | 1351 ms | 4 |
| 20.205.243.x | 2164 ms | 9 |

如果你在别的地区，这张表未必适用 —— 那种情况下用桌面版在本机实测更准。
