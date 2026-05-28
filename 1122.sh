#!/bin/bash

# =================================================================
# 脚本名称: Xray 双协议自动化管理脚本
# 脚本版本: v1.6 (精准链接解析对齐版)
# 适用系统: Ubuntu / Debian (x86_64 / arm64)
# 支持协议: VLESS-XTLS-Reality / VLESS+WS 免流
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

# 1. 安装或更新 Xray 核心
install_xray_core() {
    echo -e "${BLUE}[+] 正在调用官方脚本下载/更新核心...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --logrotate
    echo -e "${GREEN}[+] 核心部署成功！${NC}"
}

# 2. 完全卸载 Xray
uninstall_xray() {
    clear
    echo -e "${RED}==================================================${NC}"
    echo -e "${RED}             正在卸载 Xray 核心及配置              ${NC}"
    echo -e "${RED}==================================================${NC}"
    read -p "确定要完全卸载 Xray 吗？该操作不可逆！[y/N]: " CONFIRM_UNINSTALL
    if [[ "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[+] 正在调用官方卸载程序...${NC}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
        echo -e "${BLUE}[+] 正在清理残留配置文件与日志...${NC}"
        rm -rf /usr/local/etc/xray
        rm -rf /var/log/xray
        echo -e "${GREEN}[+] 卸载完成，所有相关核心、配置及日志已彻底清除。${NC}"
    else
        echo -e "${YELLOW}[+] 已取消卸载操作。${NC}"
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
        echo -e "${RED}提示：未检测到配置文件，请先选择选项 1 进行全新安装。${NC}"
        read -p "按回车键返回主菜单..." dummy
        return
    fi

    SERVER_IP=$(curl -s ipv4.icanhazip.com)
    
    echo -e "${YELLOW}【原始 config.json 内容】${NC}"
    cat "$CONFIG_FILE"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${YELLOW}【解析生成的客户端导入链接】${NC}"

    # 纯 Bash 解析 Reality 链接 (修复错位提取)
    if grep -q '"security": "reality"' "$CONFIG_FILE"; then
        PORT_REALITY=$(grep -B 5 '"security": "reality"' "$CONFIG_FILE" | grep '"port"' | head -n 1 | tr -d -c '0-9')
        UUID_REALITY=$(grep -B 5 '"security": "reality"' "$CONFIG_FILE" | grep '"id"' | head -n 1 | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="id") print $(i+2)}')
        DEST=$(grep '"dest"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="dest") print $(i+2)}' | awk -F':' '{print $1}')
        PRIV_KEY=$(grep '"privateKey"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="privateKey") print $(i+2)}')
        SHORT_ID=$(grep '"shortIds"' "$CONFIG_FILE" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="shortIds") print $(i+2)}')
        
        PUBLIC_KEY=""
        if [ -n "$PRIV_KEY" ] && [ -f "$XRAY_BIN" ]; then
            PUBLIC_KEY=$($XRAY_BIN x25519 -i "$PRIV_KEY" 2>/dev/null | grep "Public key:" | awk '{print $3}')
        fi

        if [ -n "$UUID_REALITY" ] && [ -n "$PORT_REALITY" ]; then
            REALITY_LINK="vless://${UUID_REALITY}@${SERVER_IP}:${PORT_REALITY}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${DEST}&sid=${SHORT_ID}#Reality_${SERVER_IP}"
            echo -e "${PURPLE}[+] VLESS-XTLS-Reality [抗封锁] 链接:${NC}"
            echo -e "${CYAN}${REALITY_LINK}${NC}"
            echo -e "--------------------------------------------------"
        fi
    fi

    # 纯 Bash 解析 VLESS+WS 免流链接 (精准对齐标准导入格式)
    if grep -q '"network": "ws"' "$CONFIG_FILE"; then
        PORT_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"port"' | tail -n 1 | tr -d -c '0-9')
        UUID_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"id"' | tail -n 1 | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="id") print $(i+2)}')
        HOST_NAME="t7z.cupid.iqiyi.com"
        
        if [ -n "$UUID_WS" ] && [ -n "$PORT_WS" ]; then
            WS_LINK="vless://${UUID_WS}@${SERVER_IP}:${PORT_WS}?path=%2F&security=&encryption=none&host=${HOST_NAME}&type=ws#VLESS_WS_${SERVER_IP}"
            echo -e "${PURPLE}[+] VLESS+WebSocket [免流专用] 链接:${NC}"
            echo -e "${CYAN}${WS_LINK}${NC}"
            echo -e "--------------------------------------------------"
        fi
    fi

    read -p "按回车键返回主菜单..." dummy
}

# 4. 灵活配置向导
config_xray_flexible() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}              Xray 协议自定义配置面板               ${NC}"
    echo -e "${BLUE}==================================================${NC}"

    ENABLE_REALITY=false
    ENABLE_WS=false

    # 4.1 询问配置 Reality
    read -p "是否启用 VLESS-XTLS-Reality？[y/N]: " CHOOSE_REALITY
    if [[ "$CHOOSE_REALITY" =~ ^[Yy]$ ]]; then
        ENABLE_REALITY=true
        
        echo -e "\n${YELLOW}▶ Reality 端口设置${NC}"
        echo -e "1. 随机自动生成高端口 [10000-65535]\n2. 手动输入自定义端口"
        read -p "请选择 [默认 1]: " REALITY_PORT_CHOICE
        if [ "${REALITY_PORT_CHOICE:-1}" -eq 2 ]; then
            read -p "请输入端口 [默认 443]: " PORT_REALITY
            PORT_REALITY=${PORT_REALITY:-443}
        else
            PORT_REALITY=$((RANDOM % 55536 + 10000))
        fi

        echo -e "\n${YELLOW}▶ Reality UUID 设置${NC}"
        echo -e "1. 随机自动生成 [推荐]\n2. 手动输入自定义 UUID"
        read -p "请选择 [默认 1]: " REALITY_UUID_CHOICE
        if [ "${REALITY_UUID_CHOICE:-1}" -eq 2 ]; then
            read -p "请输入 UUID: " USER_REALITY_UUID
            UUID_REALITY=${USER_REALITY_UUID:-$($XRAY_BIN uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)}
        else
            UUID_REALITY=$($XRAY_BIN uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        fi

        echo -e ""
        read -p "请输入 Reality 伪装目标网站 [默认 www.microsoft.com]: " DEST
        DEST=${DEST:-www.microsoft.com}
    fi

    # 4.2 询问配置 VLESS+WS 免流
    echo -e "${BLUE}--------------------------------------------------${NC}"
    read -p "是否启用 VLESS+WS [免流方案]？[y/N]: " CHOOSE_WS
    if [[ "$CHOOSE_WS" =~ ^[Yy]$ ]]; then
        ENABLE_WS=true

        echo -e "\n${YELLOW}▶ VLESS+WS 端口设置${NC}"
        echo -e "1. 使用免流推荐端口 [80]\n2. 手动输入自定义端口"
        read -p "请选择 [默认 1]: " WS_PORT_CHOICE
        
        ws_port_loop=true
        while [ "$ws_port_loop" = true ]; do
            if [ "${WS_PORT_CHOICE:-1}" -eq 2 ]; then
                read -p "请输入端口 [默认 21985]: " PORT_WS
                PORT_WS=${PORT_WS:-21985}
            else
                PORT_WS=80
            fi

            if [ "$ENABLE_REALITY" = true ] && [ "$PORT_REALITY" -eq "$PORT_WS" ]; then
                echo -e "${RED}错误：WS 端口不能与 Reality 端口 [${PORT_REALITY}] 冲突！${NC}"
                WS_PORT_CHOICE=2 
            else
                ws_port_loop=false
            fi
        done

        echo -e "\n${YELLOW}▶ VLESS+WS UUID 设置${NC}"
        echo -e "1. 随机自动生成\n2. 手动输入自定义 UUID"
        read -p "请选择 [默认 1]: " WS_UUID_CHOICE
        if [ "${WS_UUID_CHOICE:-1}" -eq 2 ]; then
            read -p "请输入 UUID [回车使用默认]: " USER_WS_UUID
            UUID_WS=${USER_WS_UUID:-"afba2d6a-64de-48af-9014-1734c432a893"}
        else
            UUID_WS=$($XRAY_BIN uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        fi
    fi

    if [ "$ENABLE_REALITY" = false ] && [ "$ENABLE_WS" = false ]; then
        echo -e "${RED}错误：未选择任何协议，未变更任何配置。${NC}"
        read -p "按回车键返回..." dummy
        return
    fi

    # 动态拼接 Inbounds JSON
    INBOUNDS_JSON=""

    if [ "$ENABLE_REALITY" = true ]; then
        KEYS=$($XRAY_BIN x25519)
        PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
        SHORT_ID=$(openssl rand -hex 8)

        REALITY_JSON=$(cat <<EOF
        {
          "port": $PORT_REALITY,
          "protocol": "vless",
          "settings": {
            "clients": [{ "id": "$UUID_REALITY", "flow": "xtls-rprx-vision" }],
            "decryption": "none"
          },
          "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
              "show": false,
              "dest": "$DEST:443",
              "xver": 0,
              "serverNames": ["$DEST"],
              "privateKey": "$PRIVATE_KEY",
              "shortIds": ["$SHORT_ID"]
            }
          }
        }
EOF
)
        INBOUNDS_JSON="$REALITY_JSON"
    fi

    if [ "$ENABLE_WS" = true ]; then
        WS_JSON=$(cat <<EOF
        {
          "port": $PORT_WS,
          "protocol": "vless",
          "settings": {
            "clients": [{ "id": "$UUID_WS", "level": 0 }],
            "decryption": "none"
          },
          "streamSettings": {
            "network": "ws",
            "wsSettings": { "path": "/" }
          }
        }
EOF
)
        if [ -n "$INBOUNDS_JSON" ]; then
            INBOUNDS_JSON="$INBOUNDS_JSON, $WS_JSON"
        else
            INBOUNDS_JSON="$WS_JSON"
        fi
    fi

    # 强制创建父文件夹
    mkdir -p /usr/local/etc/xray

    # 写入文件
    cat <<EOF > "$CONFIG_FILE"
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    $INBOUNDS_JSON
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
    ]
  }
}
EOF

    # 重新整理服务并展示新配置
    systemctl restart xray >/dev/null 2>&1
    view_current_config
}

# 主菜单循环
while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    Xray 自动化管理脚本 稳定版 v1.6     ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e " 1. 一键安装 Xray 并配置新协议"
    echo -e " 2. 修改 / 覆盖现有协议配置"
    echo -e " 3. 查看当前协议配置与链接"
    echo -e " 4. 仅更新 Xray 核心版本"
    echo -e " 5. 一键卸载 Xray 核心及配置"
    echo -e " 0. 退出脚本"
    echo -e "${GREEN}========================================${NC}"
    read -p "请选择操作 [0-5]: " choice

    case $choice in
        1)
            install_xray_core
            config_xray_flexible
            ;;
        2)
            if [ ! -f "$XRAY_BIN" ]; then
                echo -e "${RED}错误：本地未安装 Xray 核心，请先选择 1 安装核心！${NC}"
                read -p "按回车键继续..." dummy
                continue
            fi
            config_xray_flexible
            ;;
        3)
            view_current_config
            ;;
        4)
            install_xray_core
            systemctl restart xray >/dev/null 2>&1
            echo -e "${GREEN}[+] Xray 核心更新成功并已重启！${NC}"
            read -p "按回车键继续..." dummy
            ;;
        5)
            uninstall_xray
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入，请重新选择！${NC}"
            sleep 1
            ;;
    esac
done
