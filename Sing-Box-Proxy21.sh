#!/bin/bash
# =====================================================
# Sing-Box TProxy 完整一键部署脚本 (最终版)
# 功能：安装 Sing-Box + 配置 TProxy（IPv4 + IPv6 + 自动检测恢复）
# 适用于 Debian 12+ / Ubuntu 22+
# 作者: Duang X Scu
# =====================================================

set -e

echo "=============================================="
echo "🚀 Sing-Box TProxy 完整部署开始"
echo "=============================================="

# =====================================================
# 第一部分：安装 Sing-Box
# =====================================================
echo ""
echo "📦 第一步：安装 Sing-Box..."
echo "=============================================="

# 更新软件源
echo "正在更新软件源..."
apt update -y

# 安装必要工具
echo "正在安装必要工具..."
apt install -y curl wget iptables iproute2 iptables-persistent ca-certificates

# 更新证书
echo "正在更新证书..."
update-ca-certificates

# 创建 Sing-Box 目录
echo "正在创建目录结构..."
mkdir -p /etc/TProxy

# GitHub 加速代理（可根据需要修改）
GITHUB_PROXY="https://ghfast.top/"

# 下载 Sing-Box 二进制文件
echo "正在下载 Sing-Box 二进制文件..."
wget --timeout=30 --tries=3 -O /etc/TProxy/sing-box-1.13.0 "${GITHUB_PROXY}https://raw.githubusercontent.com/Scu13/TProxy/refs/heads/main/sing-box/sing-box-1.13.0"

if [ ! -f /etc/TProxy/sing-box-1.13.0 ]; then
    echo "❌ 错误：二进制文件下载失败！"
    exit 1
fi

# 验证文件大小
FILE_SIZE=$(stat -c%s /etc/TProxy/sing-box-1.13.0)
if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo "⚠️ 警告：二进制文件可能不完整（大小：$FILE_SIZE 字节）"
fi

# 下载配置文件
echo "正在下载 Sing-Box 配置文件..."
wget --timeout=30 --tries=3 -O /etc/TProxy/config.json "${GITHUB_PROXY}https://raw.githubusercontent.com/Scu13/TProxy/refs/heads/main/sing-box/config.json"

if [ ! -f /etc/TProxy/config.json ]; then
    echo "❌ 错误：配置文件下载失败！"
    exit 1
fi

# 设置二进制文件权限
echo "正在设置执行权限..."
chmod +x /etc/TProxy/sing-box-1.13.0

# 验证二进制文件
echo "正在验证 Sing-Box 二进制文件..."
echo "系统架构: $(uname -m)"
file /etc/TProxy/sing-box-1.13.0

if /etc/TProxy/sing-box-1.13.0 version &>/dev/null; then
    echo "✅ 二进制文件可以正常执行"
    /etc/TProxy/sing-box-1.13.0 version
else
    echo "⚠️ 警告：无法执行二进制文件，可能需要检查架构兼容性"
fi

# 修复配置文件中的代理地址（移除失效的 gh-proxy.com）
echo "正在检查配置文件..."
if grep -q "gh-proxy.com" /etc/TProxy/config.json; then
    echo "检测到 gh-proxy.com 代理，正在移除..."
    cp /etc/TProxy/config.json /etc/TProxy/config.json.backup
    sed -i 's|https://gh-proxy.com/||g' /etc/TProxy/config.json
    echo "✅ 已移除 gh-proxy.com 代理前缀"
fi

# 验证配置文件
echo "正在验证配置文件..."
if /etc/TProxy/sing-box-1.13.0 check -c /etc/TProxy/config.json; then
    echo "✅ 配置文件验证通过"
else
    echo "⚠️ 警告：配置文件验证失败，显示详细信息："
    /etc/TProxy/sing-box-1.13.0 check -c /etc/TProxy/config.json || true
    echo ""
    echo "提示：首次启动时会自动下载规则集，可能需要几分钟"
fi

# 创建 Sing-Box systemd 服务文件
echo "正在创建 Sing-Box systemd 服务..."
cat > /etc/systemd/system/TProxy-SING_BOX.service <<'EOF'
[Unit]
Description=TProxy Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target tproxy.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/TProxy
ExecStart=/etc/TProxy/sing-box-1.13.0 run -c /etc/TProxy/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
StartLimitInterval=300
StartLimitBurst=5
LimitNOFILE=1048576
LimitNPROC=512
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Sing-Box 安装完成！"

# =====================================================
# 第二部分：配置 TProxy 环境
# =====================================================
echo ""
echo "🔧 第二步：配置 TProxy 环境..."
echo "=============================================="

# 创建 tproxy 目录
mkdir -p /etc/tproxy

# =====================================================
# 创建 TProxy 规则脚本
# =====================================================
echo "正在创建 TProxy 规则脚本..."
cat > /etc/tproxy/tproxy.sh <<'TPROXY_SCRIPT'
#!/bin/bash
# ========== Sing-Box TProxy IPv4 + IPv6 配置脚本（自愈版） ==========

LOG_FILE="/var/log/tproxy.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "🕒 [$(date)] 开始加载 TProxy 规则..."

# TProxy 端口
TPROXY_PORT=7894

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
iptables -t mangle -N SING_BOX 2>/dev/null || true
iptables -t mangle -F SING_BOX

iptables -t mangle -A SING_BOX -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A SING_BOX -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A SING_BOX -d 240.0.0.0/4 -j RETURN

iptables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
iptables -t mangle -A SING_BOX -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

iptables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
iptables -t mangle -A PREROUTING -j SING_BOX

# =====================================================
# IPv6 规则
# =====================================================
ip6tables -t mangle -N SING_BOX 2>/dev/null || true
ip6tables -t mangle -F SING_BOX

ip6tables -t mangle -A SING_BOX -d ::1/128 -j RETURN
ip6tables -t mangle -A SING_BOX -d fe80::/10 -j RETURN
ip6tables -t mangle -A SING_BOX -d fc00::/7 -j RETURN
ip6tables -t mangle -A SING_BOX -d ff00::/8 -j RETURN

ip6tables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
ip6tables -t mangle -A SING_BOX -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

ip6tables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
ip6tables -t mangle -A PREROUTING -j SING_BOX

# =====================================================
# 启用内核参数
# =====================================================
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 保存规则
netfilter-persistent save

echo "✅ [$(date)] IPv4 + IPv6 TProxy 规则已加载完成！"
TPROXY_SCRIPT

chmod +x /etc/tproxy/tproxy.sh

# =====================================================
# 创建检测与自动恢复脚本
# =====================================================
echo "正在创建 TProxy 检测脚本..."
cat > /etc/tproxy/tproxy-check.sh <<'CHECK_SCRIPT'
#!/bin/bash
# ========== Sing-Box TProxy 检测与自动恢复脚本 ==========

LOG_FILE="/var/log/tproxy-check.log"
exec > >(tee -a $LOG_FILE) 2>&1

check_and_reload() {
    local proto=$1
    local cmd=$2

    echo "🔍 检查 ${proto} 规则状态..."

    if ! $cmd -t mangle -L SING_BOX &>/dev/null; then
        echo "⚠️ 检测到 ${proto} TProxy 规则缺失，正在重新加载..."
        bash /etc/tproxy/tproxy.sh
    else
        if ! $cmd -t mangle -L SING_BOX -v -n | grep -q "TPROXY"; then
            echo "⚠️ 检测到 ${proto} TProxy 规则异常，重新加载中..."
            bash /etc/tproxy/tproxy.sh
        else
            echo "✅ ${proto} TProxy 规则正常。"
        fi
    fi
}

check_and_reload "IPv4" "iptables"
check_and_reload "IPv6" "ip6tables"
CHECK_SCRIPT

chmod +x /etc/tproxy/tproxy-check.sh

# =====================================================
# 创建 TProxy systemd 服务
# =====================================================
echo "正在创建 TProxy systemd 服务..."
cat > /etc/systemd/system/tproxy.service <<'TPROXY_SERVICE'
[Unit]
Description=Sing-Box TProxy 规则加载（IPv4 + IPv6 + 自动检测）
After=network-online.target
Wants=network-online.target
Before=TProxy-SING_BOX.service

[Service]
Type=oneshot
ExecStart=/etc/tproxy/tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TPROXY_SERVICE

cat > /etc/systemd/system/tproxy-check.timer <<'TIMER_SERVICE'
[Unit]
Description=定期检测并自动恢复 TProxy 规则

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=tproxy-check.service

[Install]
WantedBy=multi-user.target
TIMER_SERVICE

cat > /etc/systemd/system/tproxy-check.service <<'CHECK_SERVICE'
[Unit]
Description=Sing-Box TProxy 自动检测与恢复
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/tproxy/tproxy-check.sh
CHECK_SERVICE

echo "✅ TProxy 环境配置完成！"

# =====================================================
# 第三步：启动所有服务
# =====================================================
echo ""
echo "🎯 第三步：启动服务..."
echo "=============================================="

# 重新加载 systemd
systemctl daemon-reload

# 启用并启动 TProxy 规则服务
echo "正在启动 TProxy 规则服务..."
systemctl enable tproxy.service
systemctl start tproxy.service

# 启用定时检测
echo "正在启用 TProxy 定时检测..."
systemctl enable tproxy-check.timer
systemctl start tproxy-check.timer

# 启用并启动 Sing-Box 服务
echo "正在启动 Sing-Box 服务..."
systemctl enable TProxy-SING_BOX.service
systemctl start TProxy-SING_BOX.service

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 检查服务是否正常运行
if systemctl is-active --quiet TProxy-SING_BOX.service; then
    echo "✅ Sing-Box 服务启动成功"
else
    echo "⚠️ Sing-Box 服务未能正常启动，显示详细日志："
    journalctl -u TProxy-SING_BOX.service -n 50 --no-pager
    echo ""
    echo "💡 尝试手动运行以排查问题："
    echo "   cd /etc/TProxy && ./sing-box-1.13.0 run -c config.json"
fi

# =====================================================
# 显示部署结果
# =====================================================
echo ""
echo "=============================================="
echo "✅ 部署完成！"
echo "=============================================="
echo ""
echo "📂 安装目录："
echo "   Sing-Box: /etc/TProxy/"
echo "   TProxy 脚本: /etc/tproxy/"
echo ""
echo "🔧 服务管理命令："
echo "   查看 Sing-Box 状态: systemctl status TProxy-SING_BOX"
echo "   查看 TProxy 状态: systemctl status tproxy"
echo "   查看定时检测: systemctl list-timers | grep tproxy"
echo ""
echo "   重启 Sing-Box: systemctl restart TProxy-SING_BOX"
echo "   重启 TProxy: systemctl restart tproxy"
echo "   停止 Sing-Box: systemctl stop TProxy-SING_BOX"
echo ""
echo "📜 日志查看："
echo "   实时日志: journalctl -u TProxy-SING_BOX -f"
echo "   最近日志: journalctl -u TProxy-SING_BOX -n 100"
echo "   TProxy 规则日志: cat /var/log/tproxy.log"
echo "   TProxy 检测日志: cat /var/log/tproxy-check.log"
echo ""
echo "🔍 故障排查："
echo "   手动测试运行: cd /etc/TProxy && ./sing-box-1.13.0 run -c config.json"
echo "   验证配置: /etc/TProxy/sing-box-1.13.0 check -c /etc/TProxy/config.json"
echo "   查看二进制信息: file /etc/TProxy/sing-box-1.13.0"
echo "   修复配置代理: sed -i 's|https://gh-proxy.com/||g' /etc/TProxy/config.json"
echo ""
echo "=============================================="
echo "🎉 所有服务状态："
echo "=============================================="
echo ""

# 显示服务状态
echo "📊 Sing-Box 服务状态："
systemctl status TProxy-SING_BOX --no-pager -l || true
echo ""

# 如果服务失败，显示最近的日志
if ! systemctl is-active --quiet TProxy-SING_BOX.service; then
    echo "❌ Sing-Box 服务未运行，显示最近 30 行日志："
    journalctl -u TProxy-SING_BOX.service -n 30 --no-pager
    echo ""
fi

echo "📊 TProxy 规则服务状态："
systemctl status tproxy --no-pager -l || true
echo ""

echo "📊 TProxy 定时检测状态："
systemctl list-timers --no-pager | grep tproxy || true
echo ""

echo "✅ 部署脚本执行完毕！"
echo ""
echo "📌 下一步操作："
echo "   1. 如果 Sing-Box 未正常启动，请检查配置文件中的规则集代理地址"
echo "   2. 修改配置后重启服务: systemctl restart TProxy-SING_BOX"
echo "   3. 首次启动需要下载规则集，请耐心等待 1-5 分钟"
