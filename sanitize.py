#!/usr/bin/env python3
"""
脱敏脚本（公开版 / 规则模板）。

⚠️ 本文件是**规则模板**，不是可立即运行的脱敏工具。
   原始字面量（硬件序列号、真实家目录路径、邮箱等）已从本文件移除，
   请从你的私有归档中取回 sanitize.py 使用。

用法（需先补全下面的 <...> 占位符）:
    python3 sanitize.py <原始工作区> <输出目录>

设计原则:
  - 只做文本替换 + 文件筛选，绝不修改源目录
  - 所有替换规则集中在此，便于审查
  - 序列号 / 硬件指纹一律替换为占位符
"""

import os
import re
import shutil
import sys

# ---------------------------------------------------------------------------
# 替换规则（按顺序应用，长串优先）
#
# ⚠️ 公开版已把敏感字面量替换为 <...> 说明。
#    要真正跑起来，请把每个 <...> 换成你的私有归档里的原始值。
# ---------------------------------------------------------------------------
REPLACEMENTS = [
    # --- 硬件指纹（最高优先级，先替换长串）---
    ("<16位bootloader序列号>", "<SERIALNO>"),
    ("<16位CPU序列号>", "<CPU-SERIAL>"),

    # --- 源码树路径（长的在前，避免被短规则二次命中）---
    ("/home/<user>/<dev>/LubanCat_SDK", "$LUBANCAT_SDK"),
    ("/home/<user>/<dev>/openharmony-lts", "$OH_SRC"),
    ("/home/<user>/<dev>", "$DEV_HOME"),
    ("/home/<user>", "$HOME"),

    # --- 相对路径形式（markdown 链接里引用源码树）---
    ("../../<dev>/openharmony-lts/", "../../$OH_SRC/"),
    ("../../<dev>/", "../../$DEV_HOME/"),
    ("<dev>/openharmony-lts", "$OH_SRC"),
    ("<dev>/LubanCat_SDK", "$LUBANCAT_SDK"),
    ("<dev>/OH6.1_BUILD_STATUS.md", "$DEV_HOME/OH6.1_BUILD_STATUS.md"),
    ("<dev>", "$DEV_HOME"),

    # --- Windows 路径 ---
    (r"D:\<flash目录名>", "<FLASH_DIR>"),
    (r"D:\<工具目录>\RKDevTool_Release_v<版本号>\...\RKDevTool.exe", "<RKDEVTOOL>"),
    (r"/mnt/d/<IDE目录>/hdc.exe", "<HDC>"),
    (r"/mnt/d/<flash目录名>", "<FLASH_DIR>"),
    (r'D:\...\', "<FLASH_DIR>/..."),
    (r"/mnt/d/", "<WIN_DRIVE>/"),

    # --- 内网 IP（板子实际地址 → 示例地址）---
    # 说明：把 192.168.<你的网段>.<板子实际IP> 替换为 192.168.x.<同一IP>
    # 下面四条是示例，请按你的实际网段与 IP 增删
    ("192.168.<网段>.<板子IP-1>", "192.168.x.<板子IP-1>"),
    ("192.168.<网段>.<板子IP-2>", "192.168.x.<板子IP-2>"),
    ("192.168.<网段>.<板子IP-3>", "192.168.x.<板子IP-3>"),
    ("192.168.<网段>.1", "192.168.x.1"),

    # --- git 身份（防御性，防止 ~/.gitconfig 内容漏入文档）---
    ("<个人邮箱>", "<EMAIL>"),
]

# 需要跳过的目录/文件名（构建垃圾、上游第三方、无价值产物）
SKIP_DIRS = {
    "untracked-files",       # 857 个上游未跟踪文件 + 构建垃圾，无移植内容
    ".git",
    "node_modules",
}

SKIP_FILES = {
    "repo-status-porcelain.txt",  # 只是 repo 命令报错记录
    "applications_standard_launcher.patch",  # 0 字节
    "device_board_embedfire.patch",          # 0 字节
}

# 只保留这些顶层文档/目录
KEEP_TOP = {
    "01-总体规划与当前状态.md",
    "02-风险清单与知识迁移.md",
    "03-编译排查与内核适配.md",
    "04-调试与操作手册.md",
    "05-6.1进展与当前状态.md",
    "08-ArkUI输入链路核实与自检开关.md",
    "Launcher_3745.db",
    "desktop_3745.jpeg",
    "launcher_boot_3745.log",
    "diag-map-failed.sh",
    "setup-openharmony-kernel.sh",
    "setup-serial-perm.sh",
    "README.md",
    "06-启动日志-20260816-binder失败.log",
    "07-启动日志-20260816-bootcomplete-softbus循环.log",
    "patches",
    "patches-2in1-dpi",
    "research-pc-2in1",
    "forensic-20261008",
    "screenshots",
    "changes-5.0.3",
}


def sanitize_bytes(data):
    """对字节数据应用所有替换，返回 (新数据, 替换次数)。"""
    count = 0
    for old, new in REPLACEMENTS:
        ob = old.encode("utf-8")
        nb = new.encode("utf-8")
        n = data.count(ob)
        if n:
            data = data.replace(ob, nb)
            count += n
    return data, count


def should_skip_file(rel, name):
    if name in SKIP_FILES:
        return True
    # 跳过 .orig / .bak / 中间产物
    if name.endswith((".orig", ".bak", ".bad", ".prev", ".orig-wmfix")):
        return True
    return False


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src = os.path.abspath(sys.argv[1])
    dst = os.path.abspath(sys.argv[2])

    if not os.path.isdir(src):
        sys.exit(f"源目录不存在: {src}")
    if os.path.exists(dst):
        sys.exit(f"目标已存在，请先删除: {dst}")

    total_files = 0
    total_repl = 0
    skipped = []

    for root, dirs, files in os.walk(src):
        rel_root = os.path.relpath(root, src)

        # 目录级过滤
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        if rel_root == ".":
            # 顶层只保留白名单
            dirs[:] = [d for d in dirs if d in KEEP_TOP]

        for name in files:
            rel = os.path.relpath(os.path.join(root, name), src)
            if rel_root == "." and name not in KEEP_TOP:
                skipped.append(rel)
                continue
            if should_skip_file(rel, name):
                skipped.append(rel)
                continue

            s = os.path.join(root, name)
            d = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(d), exist_ok=True)

            try:
                with open(s, "rb") as f:
                    data = f.read()
            except OSError as e:
                print(f"  [跳过] 读失败 {rel}: {e}")
                skipped.append(rel)
                continue

            new_data, n = sanitize_bytes(data)

            # 二进制且无替换 → 原样复制；有替换则必须能按 UTF-8 解码才写回
            try:
                new_data.decode("utf-8")
            except UnicodeDecodeError:
                if n > 0:
                    print(f"  [警告] {rel} 是二进制但有替换，按字节写入")
                shutil.copy2(s, d) if n == 0 else None
                if n == 0:
                    total_files += 1
                    continue

            with open(d, "wb") as f:
                f.write(new_data)

            total_files += 1
            total_repl += n
            if n:
                print(f"  [清洗] {rel}: {n} 处")

    print()
    print(f"完成: {total_files} 个文件, {total_repl} 处替换")
    print(f"跳过: {len(skipped)} 个")
    if skipped:
        print("跳过清单（前 20）:")
        for s in skipped[:20]:
            print("   ", s)


if __name__ == "__main__":
    main()
