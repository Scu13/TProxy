#!/bin/bash

# 更新系统并安装ipset
echo "安装 ipset..."
apt-get update && apt-get install -y ipset

# 创建ipset规则文件目录
echo "创建 /etc/iptables 目录..."
mkdir -p /etc/iptables

# 创建local_ip集合并添加IP
echo "创建 local_ip 集合并添加 IP..."
ipset create local_ip hash:net
ipset add local_ip 0.0.0.0/8
ipset add local_ip 10.0.0.0/8
ipset add local_ip 127.0.0.0/8
ipset add local_ip 169.254.0.0/16
ipset add local_ip 172.16.0.0/12
ipset add local_ip 192.168.0.0/16
ipset add local_ip 224.0.0.0/4
ipset add local_ip 240.0.0.0/4

# 保存ipset规则
echo "保存 ipset 规则..."
ipset save > /etc/iptables/ipset_rules.ipv4

# 配置iptables规则
echo "配置 iptables 规则..."
iptables -t mangle -N MIHOMO
iptables -t mangle -A MIHOMO -p tcp -m set --match-set local_ip dst -j RETURN
iptables -t mangle -A MIHOMO -p udp -m set --match-set local_ip dst -m udp ! --dport 53 -j RETURN
iptables -t mangle -A MIHOMO -p udp -j TPROXY --on-port 9420 --tproxy-mark 1
iptables -t mangle -A MIHOMO -p tcp -j TPROXY --on-port 9420 --tproxy-mark 1
iptables -t mangle -A PREROUTING -j MIHOMO

# 保存iptables规则
echo "保存 iptables 规则..."
iptables-save > /etc/iptables/iptables_rules.ipv4

# 创建 systemd 服务，设置开机自启
echo "创建 MIHOMO 开机自启服务..."
cat <<EOF > /etc/systemd/system/mihomo.service
[Unit]
Description=Mihomo Tproxy rule
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip rule add fwmark 1 table 100 ; /sbin/ip route add local 0.0.0.0/0 dev lo table 100 ; /sbin/ipset restore -file /etc/iptables/ipset_rules.ipv4 ; /sbin/iptables-restore /etc/iptables/iptables_rules.ipv4

[Install]
WantedBy=multi-user.target
EOF

# 启用 mihomo 服务
echo "启用 MIHOMO 服务..."
systemctl enable mihomo

# 启动服务
echo "启动 MIHOMO 服务..."
systemctl start mihomo

# 完成
echo "一键配置完成！现在可以重启系统来测试自动恢复..."
