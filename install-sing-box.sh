#!/bin/bash

# 更新软件源
echo "正在更新软件源..."
apt update

# 安装必要工具
echo "正在安装curl和wget..."
apt install -y curl wget

# 更新证书
echo "正在更新证书..."
apt install -y ca-certificates
update-ca-certificates

# 创建目标目录
mkdir -p /etc/TProxy

# 下载Sing-box二进制文件
echo "正在下载Sing-box二进制文件..."
wget -O /etc/TProxy/sing-box-1.13.0 https://raw.githubusercontent.com/Scu13/TProxy/refs/heads/main/sing-box/sing-box-1.13.0

# 下载配置文件
echo "正在下载配置文件..."
wget -O /etc/TProxy/config.json https://raw.githubusercontent.com/Scu13/TProxy/refs/heads/main/sing-box/config.json

# 设置二进制文件权限
chmod +x /etc/TProxy/sing-box-1.13.0

# 创建systemd服务文件
echo "正在创建systemd服务文件..."
cat > /etc/systemd/system/TProxy.service <<EOF
[Unit]
Description=TProxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/TProxy
ExecStart=/etc/TProxy/sing-box-1.13.0 run -c config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
systemctl daemon-reload

# 启用并启动服务
systemctl enable TProxy
systemctl start TProxy

# 检查服务状态
echo "服务状态:"
systemctl status TProxy

echo "安装完成！"
