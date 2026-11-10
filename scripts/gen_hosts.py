#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 docs/hosts.txt

策略：拉取多个公开源，按「同一 IP 被几个源同时给出」投票排序。
      多源共识比单源更可能稳定 —— 但这不是本机实测，
      要最贴合自己线路的结果请用桌面版工具。

用法：python scripts/gen_hosts.py
"""

import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

SOURCES = [
    ("GitHub520", "https://raw.hellogithub.com/hosts"),
    ("ittuann", "https://cdn.jsdelivr.net/gh/ittuann/GitHub-IP-hosts@main/hosts"),
    ("Licoy", "https://hosts.gitcdn.top/hosts.txt"),
]

DOMAINS = [
    "github.com",
    "api.github.com",
    "raw.githubusercontent.com",
    "camo.githubusercontent.com",
    "github.githubassets.com",
    "avatars.githubusercontent.com",
    "objects.githubusercontent.com",
    "codeload.github.com",
    "user-images.githubusercontent.com",
    "release-assets.githubusercontent.com",
]

MAX_PER_DOMAIN = 4
UA = "L1-GitHub-Hosts/1.0 (+https://github.com/gooooddayy/L1-github-hosts)"

# 实测分层：数值越小越优先。
# 来源是 2026-11 在中国大陆线路上做的完整链路测量（TCP + TLS + 首字节）：
#   20.27.177    ≈ 719ms      140.82.114 ≈ 975ms
#   140.82.113   ≈ 1173ms     140.82.112 ≈ 1351ms
#   185.199.*    Fastly CDN，长期稳定
#   20.205.243   ≈ 2164ms —— Azure 东亚，是 DNS 默认值但明显偏慢
# 多源共识只说明「这个 IP 存在且被认可」，不说明它在你这条线上快，
# 所以先用实测分层过滤，再按票数排序。
TIER = {
    "20.27.177": 1,
    "140.82.114": 2,
    "185.199": 2,
    "140.82.113": 3,
    "140.82.112": 4,
    "20.205.243": 9,
}
TIER_DEFAULT = 5


def tier_of(ip):
    head = ".".join(ip.split(".")[:2])
    for key, val in TIER.items():
        if ip.startswith(key + "."):
            return val
    return TIER_DEFAULT


LINE_RE = re.compile(r"^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([A-Za-z0-9][A-Za-z0-9.\-]*)")


def fetch(url, timeout=12):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def parse(text):
    table = {}
    for line in text.splitlines():
        if not line or line.lstrip().startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        ip, host = m.group(1), m.group(2).lower()
        table.setdefault(host, [])
        if ip not in table[host]:
            table[host].append(ip)
    return table


def main():
    sets = []
    for name, url in SOURCES:
        try:
            sets.append((name, parse(fetch(url))))
            print(f"[ok]   {name}")
        except Exception as exc:  # noqa: BLE001
            print(f"[fail] {name}: {exc}")

    if not sets:
        print("所有源都不可达，保留现有 hosts.txt 不覆盖")
        return 1

    tz = timezone(timedelta(hours=8))
    now = datetime.now(tz).strftime("%Y-%m-%d %H:%M:%S")

    lines = [
        "# L1 GitHub Hosts - 自动生成，请勿手动编辑",
        f"# 更新时间: {now} (+08:00)",
        f"# 数据来源: {len(sets)}/{len(SOURCES)} 个公开源交叉验证",
        "# 排序规则: 先按实测延迟分层（偏慢的网段排后面），同层内按多源票数",
        "# 说明: 这是多源共识结果，不是在本机实测的。",
        "#       要最贴合自己线路的结果，请用桌面版工具：",
        "#       https://github.com/gooooddayy/L1-github-hosts/releases/latest",
        "",
        "# === GitHub IP BEGIN ===",
    ]

    total = 0
    for host in DOMAINS:
        votes = {}
        for _, table in sets:
            for ip in table.get(host, []):
                votes[ip] = votes.get(ip, 0) + 1
        # 先按实测分层，同层内再按多源票数
        ranked = sorted(votes.items(), key=lambda kv: (tier_of(kv[0]), -kv[1], kv[0]))[:MAX_PER_DOMAIN]
        if not ranked:
            print(f"[warn] {host} 没有可用数据")
            continue
        for ip, _score in ranked:
            lines.append(f"{ip:<16} {host}")
            total += 1

    lines.append("# === GitHub IP END ===")
    lines.append("")

    out = "\n".join(lines)
    with open("docs/hosts.txt", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(out)

    print(f"写入 {total} 条记录 -> docs/hosts.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
