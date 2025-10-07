#!/bin/bash
# =====================================================
# Mihomo TProxy 一键部署脚本（IPv4 + IPv6 + 转发内核）
# =====================================================
set -e

echo "🔧 开始部署 Mihomo TProxy 环境..."

# 1️⃣ 安装依赖
apt update -y
apt install -y iptables iproute2 iptables-persistent curl netfilter-persistent

# 2️⃣ 启用内核参数
echo "🔧 启用内核转发..."

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.all.accept_ra=2
sysctl -w net.ipv4.conf.all.rp_filter=2

# 3️⃣ 创建 TProxy 配置脚本
cat > /etc/mihomo/tproxy.sh <<'EOF'
#!/bin/bash
# ========== Mihomo TProxy IPv4 + IPv6 配置脚本 ==========

LOG_FILE="/var/log/tproxy.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "🕒 [$(date)] 开始加载 TProxy 规则..."

# 检查是否存在 tproxy 二进制端口占用
TPROXY_PORT=9420  # 更新端口号为 9420

# 清空旧规则
iptables -t mangle -F
ip6tables -t mangle -F
iptables -t nat -F
ip6tables -t nat -F

# =====================================================
# IPv4 路由策略
# =====================================================
ip rule add fwmark 1 table 100 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null || true

# IPv6 路由策略
ip -6 rule add fwmark 1 table 100 2>/dev/null || true
ip -6 route add local ::/0 dev lo table 100 2>/dev/null || true

# =====================================================
# IPv4 规则
# =====================================================
iptables -t mangle -N MIHOMO 2>/dev/null || true
iptables -t mangle -F MIHOMO

iptables -t mangle -A MIHOMO -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A MIHOMO -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A MIHOMO -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A MIHOMO -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A MIHOMO -d 240.0.0.0/4 -j RETURN

iptables -t mangle -A MIHOMO -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
iptables -t mangle -A MIHOMO -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

iptables -t mangle -C PREROUTING -j MIHOMO 2>/dev/null || \
iptables -t mangle -A PREROUTING -j MIHOMO

# =====================================================
# IPv6 规则
# =====================================================
ip6tables -t mangle -N MIHOMO 2>/dev/null || true
ip6tables -t mangle -F MIHOMO

ip6tables -t mangle -A MIHOMO -d ::1/128 -j RETURN
ip6tables -t mangle -A MIHOMO -d fe80::/10 -j RETURN
ip6tables -t mangle -A MIHOMO -d fc00::/7 -j RETURN
ip6tables -t mangle -A MIHOMO -d ff00::/8 -j RETURN

ip6tables -t mangle -A MIHOMO -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
ip6tables -t mangle -A MIHOMO -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

ip6tables -t mangle -C PREROUTING -j MIHOMO 2>/dev/null || \
ip6tables -t mangle -A PREROUTING -j MIHOMO

# =====================================================
# 启用内核参数
# =====================================================
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 保存规则
netfilter-persistent save

echo "✅ [$(date)] IPv4 + IPv6 TProxy 规则已加载完成！"
EOF

chmod +x /etc/mihomo/tproxy.sh

# 4️⃣ 创建 systemd 服务：规则加载
cat > /etc/systemd/system/tproxy.service <<'EOF'
[Unit]
Description=Mihomo TProxy 规则加载（IPv4 + IPv6）
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/mihomo/tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 5️⃣ 启动 TProxy 服务
systemctl daemon-reload
systemctl enable tproxy.service
systemctl start tproxy.service

# 6️⃣ 检查服务状态
echo "✅ 部署完成！"
echo "请使用以下命令检查 TProxy 服务的状态:"
echo "  systemctl status tproxy.service"

# 7️⃣ 检查日志文件
echo "📜 日志文件: /var/log/tproxy.log"

chmod +x /etc/mihomo/tproxy.sh

# 运行脚本
bash /etc/mihomo/tproxy.sh

echo "✅ 完成！现在 TProxy 模式已启用，内核转发已开启！"
