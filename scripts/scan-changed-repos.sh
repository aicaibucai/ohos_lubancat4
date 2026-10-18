#!/usr/bin/env bash
# 扫描 OpenHarmony 源码树，列出有 git 改动的仓库
# 输出：/tmp/repo_changed.txt，格式 "<改动数>|<仓库路径>"
#
# 依赖：repo 工具（OH 源码树的标准管理工具）
# 用法：bash scan-changed-repos.sh
set -uo pipefail

O=${OH_SRC:?请先设置 OH_SRC 环境变量指向 OpenHarmony 源码树}
cd "$O" || exit 1

timeout 60 repo list -p 2>/dev/null > /tmp/repo_paths.txt
echo "仓库数: $(wc -l < /tmp/repo_paths.txt)"

: > /tmp/repo_changed.txt
while read -r p; do
  [ -d "$p" ] || continue
  n=$(git -C "$p" status --porcelain 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ]; then
    echo "$n|$p" >> /tmp/repo_changed.txt
  fi
done < /tmp/repo_paths.txt

echo "有改动的仓库数: $(wc -l < /tmp/repo_changed.txt)"
sort -t'|' -k1 -rn /tmp/repo_changed.txt
