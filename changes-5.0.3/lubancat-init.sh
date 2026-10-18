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
