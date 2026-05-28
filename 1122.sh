#!/bin/bash

# =================================================================
# 脚本名称: Xray 自动化管理脚本
# 脚本版本: v1.0
# 适用系统: Ubuntu / Debian (x86_64 / arm64)
# 支持协议: VLESS-XTLS-Reality / VLESS+WS
# =================================================================

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 权限运行此脚本！${NC}" 
   exit 1
fi

# 智能检查 Xray 核心安装路径
check_xray_installed() {
    if command -v xray >/dev/null 2>&1; then
        XRAY_BIN=$(command -v xray)
        return 0
    elif [ -f "/usr/local/bin/xray" ]; then
        XRAY_BIN="/usr/local/bin/xray"
        return 0
    elif [ -f "/usr/bin/xray" ]; then
        XRAY_BIN="/usr/bin/xray"
        return 0
    else
        return 1
    fi
}

# 1. 智能安装或更新 Xray 核心
install_xray_core() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}             Xray 核心安装与状态检查              ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    check_xray_installed
    if [ $? -eq 0 ]; then
        LOCAL_VER=$($XRAY_BIN version | head -n 1 | awk '{print $2}')
        echo -e "${GREEN}[+] 系统已安装 Xray 核心！当前版本: ${CYAN}v${LOCAL_VER}${NC}"
    else
        echo -e "${YELLOW}[!] 未检测到 Xray 核心，准备开始全新安装...${NC}"
    fi
    echo -e "${BLUE}[+] 正在调用官方脚本下载核心...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    read -p "按回车键返回主菜单..." dummy
}

# 4. 完全卸载 Xray
uninstall_xray() {
    clear
    read -p "确定要完全卸载 Xray 吗？该操作不可逆！[y/N]: " CONFIRM_UNINSTALL
    if [[ "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
        rm -rf /usr/local/etc/xray
        rm -rf /var/log/xray
        echo -e "${GREEN}[+] 卸载完成。${NC}"
    fi
    read -p "按回车键返回主菜单..." dummy
}

# 3. 解析并展示当前配置与链接
view_current_config() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}         当前服务器 Xray 运行配置与链接          ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}提示：未检测到配置文件，请先选择选项 2 进行配置写入。${NC}"
        read -p "按回车键返回主菜单..." dummy
        return
    fi
    SERVER_IP=$(curl -s ipv4.icanhazip.com)
    check_xray_installed
    if grep -q '"security": "reality"' "$CONFIG_FILE"; then
        PORT_REALITY=$(grep -B 5 '"security": "reality"' "$CONFIG_FILE" | grep '"port"' | head -n 1 | tr -d -c '0-9')
        UUID_REALITY=$(grep -B 5 '"security": "reality"' "$CONFIG_FILE" | grep '"id"' | head -n 1 | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="id") print $(i+2)}')
        DEST=$(grep '"dest"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="dest") print $(i+2)}' | awk -F':' '{print $1}')
        PRIV_KEY=$(grep '"privateKey"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="privateKey") print $(i+2)}')
        SHORT_ID=$(grep '"shortIds"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="shortIds") print $(i+2)}')
        PUBLIC_KEY=$($XRAY_BIN x25519 -i "$PRIV_KEY" 2>/dev/null | grep "Public key:" | awk '{print $3}')
        echo -e "${PURPLE}[+] VLESS-XTLS-Reality 链接:${NC}"
        echo -e "${CYAN}vless://${UUID_REALITY}@${SERVER_IP}:${PORT_REALITY}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${DEST}&sid=${SHORT_ID}#Reality_${SERVER_IP}${NC}"
    fi
    if grep -q '"network": "ws"' "$CONFIG_FILE"; then
        PORT_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"port"' | tail -n 1 | tr -d -c '0-9')
        UUID_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"id"' | tail -n 1 | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="id") print $(i+2)}')
        HOST_NAME=$(grep -A 5 '"wsSettings"' "$CONFIG_FILE" | grep -i '"Host"' | head -n 1 | awk -F'"' '{print $4}')
        echo -e "${PURPLE}[+] VLESS+WebSocket 链接:${NC}"
        echo -e "${CYAN}vless://${UUID_WS}@${SERVER_IP}:${PORT_WS}?path=%2F&security=&encryption=none&host=${HOST_NAME}&type=ws#VLESS_WS_${SERVER_IP}${NC}"
    fi
    read -p "按回车键返回主菜单..." dummy
}

# 2. 配置向导
config_xray_flexible() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}              Xray 协议配置管理器子菜单             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e " 1. 仅配置 VLESS-XTLS-Reality"
    echo -e " 2. 仅配置 VLESS+WS"
    echo -e " 3. 部署所有协议"
    echo -e " 0. 返回主菜单"
    echo -e "${BLUE}==================================================${NC}"
    read -p "请输入选项 [0-3]: " PROTO_CHOICE
    [ "$PROTO_CHOICE" == "0" ] && return
    
    check_xray_installed
    PORT_REALITY=443; PORT_WS=443; UUID_REALITY=$(cat /proc/sys/kernel/random/uuid); UUID_WS=$(cat /proc/sys/kernel/random/uuid); DEST="www.microsoft.com"; HOST_NAME=""
    
    [ "$PROTO_CHOICE" == "1" ] || [ "$PROTO_CHOICE" == "3" ] && { read -p "Reality 端口 [回车默认 443]: " PORT_REALITY; PORT_REALITY=${PORT_REALITY:-443}; read -p "伪装域名 [回车默认 www.microsoft.com]: " DEST; DEST=${DEST:-www.microsoft.com}; }
    [ "$PROTO_CHOICE" == "2" ] || [ "$PROTO_CHOICE" == "3" ] && { read -p "WS 端口 [回车默认 443]: " PORT_WS; PORT_WS=${PORT_WS:-443}; read -p "Host设置 [回车为空]: " HOST_NAME; }
    
    INBOUNDS_JSON=""
    if [ "$PROTO_CHOICE" == "1" ] || [ "$PROTO_CHOICE" == "3" ]; then
        PRIV_KEYS=$($XRAY_BIN x25519)
        PRIV_KEY=$(echo "$PRIV_KEYS" | grep "Private key:" | awk '{print $3}')
        SHORT_ID=$(openssl rand -hex 8)
        INBOUNDS_JSON="{\"port\": $PORT_REALITY, \"protocol\": \"vless\", \"settings\": {\"clients\": [{\"id\": \"$UUID_REALITY\", \"flow\": \"xtls-rprx-vision\"}], \"decryption\": \"none\"}, \"streamSettings\": {\"network\": \"tcp\", \"security\": \"reality\", \"realitySettings\": {\"dest\": \"$DEST:443\", \"serverNames\": [\"$DEST\"], \"privateKey\": \"$PRIV_KEY\", \"shortIds\": [\"$SHORT_ID\"]}}}"
    fi
    if [ "$PROTO_CHOICE" == "2" ] || [ "$PROTO_CHOICE" == "3" ]; then
        WS_OBJ="{\"port\": $PORT_WS, \"protocol\": \"vless\", \"settings\": {\"clients\": [{\"id\": \"$UUID_WS\", \"level\": 0}], \"decryption\": \"none\"}, \"streamSettings\": {\"network\": \"ws\", \"wsSettings\": {\"path\": \"/\", \"headers\": {\"Host\": \"$HOST_NAME\"}}}}"
        [ -n "$INBOUNDS_JSON" ] && INBOUNDS_JSON="$INBOUNDS_JSON, $WS_OBJ" || INBOUNDS_JSON="$WS_OBJ"
    fi
    mkdir -p /usr/local/etc/xray
    echo "{\"inbounds\": [ $INBOUNDS_JSON ], \"outbounds\": [{\"protocol\": \"freedom\", \"tag\": \"direct\"}, {\"protocol\": \"blackhole\", \"tag\": \"block\"}], \"routing\": {\"rules\": [{\"type\": \"field\", \"ip\": [\"geoip:private\"], \"outboundTag\": \"block\"}]}}" > "$CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1
    view_current_config
}

while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    Xray 自动化管理脚本 v1.0            ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e " 1. 检查并安装/更新 Xray 核心"
    echo -e " 2. 添加 / 修改协议配置"
    echo -e " 3. 查看当前协议配置与链接"
    echo -e " 4. 一键卸载 Xray 核心及配置"
    echo -e " 0. 退出脚本"
    echo -e "${GREEN}========================================${NC}"
    read -p "请选择操作 [0-4]: " choice
    case $choice in
        1) install_xray_core ;;
        2) config_xray_flexible ;;
        3) view_current_config ;;
        4) uninstall_xray ;;
        0) exit 0 ;;
    esac
done
