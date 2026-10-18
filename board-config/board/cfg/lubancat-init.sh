#!/system/bin/sh
# LubanCat4 board init (called by /system/etc/init/lubancat4-init.cfg boot job)
# Fix eth0 IP and default gateway so TCP hdc is reachable right after boot.

NET_IFACE=eth0
NET_IP=192.168.x.200
NET_MASK=255.255.255.0
NET_GW=192.168.x.1

# wait for the interface to show up (max ~8s)
i=0
while [ $i -lt 8 ]; do
    ifconfig $NET_IFACE up 2>/dev/null && break
    i=$((i + 1))
    sleep 1
done

# static IPv4
ifconfig $NET_IFACE $NET_IP netmask $NET_MASK up

# default gateway: prefer route, fall back to ip (both from toybox)
route add default gw $NET_GW dev $NET_IFACE 2>/dev/null
if ! route -n 2>/dev/null | grep -q '^0\.0\.0\.0'; then
    ip route add default via $NET_GW dev $NET_IFACE 2>/dev/null
fi

# ---------------------------------------------------------------------------
# [LubanCat4 bring-up 2026-10-01] 开机黑屏自愈
#
# 背景：bootanimation（init 里的 once 服务）在 BootAnimationStrategy::CheckExitAnimation()
#   里等 bootevent.boot.completed 才会退出；而本板 bootevent.launcher.ready 永不置位
#   （launcher 停在 app state #BEGIN、不建窗口）→ init 的启动事件链不完整 →
#   boot.completed 永不置位 → 动画进程一直死等、其"全屏不透明黑 SurfaceNode"
#   （BackgroundColor #FF000000 / PositionZ 100000）永不撤销 → 开机后表现为一直黑屏。
#   实测：手动 `param set bootevent.boot.completed true` 后，动画进程 6 秒内自行退出、
#   RS 树里的 BootAnimationNode 消失、黑层撤销（不需要 killall，也不会重启整机）。
#
# 兜底策略：延迟先置位该事件让动画优雅退出；若再过 30 秒进程仍在，用受管方式停服务
#   （绝不用 killall —— 那会触发整个 init 重启整机）。
# 注：这是"绕过"。根因修好后（launcher 能进前台 → launcher.ready → boot.completed 自然置位），
#   本段可直接删除。
# ---------------------------------------------------------------------------
(
    sleep 30
    param set bootevent.boot.completed true
    sleep 30
    if [ -n "$(pidof bootanimation)" ]; then
        service_control stop bootanimation
    fi
) &

