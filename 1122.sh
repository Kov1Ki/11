#!/bin/bash

# =================================================================
# 脚本名称: Xray 双协议自动化管理脚本
# 脚本版本: v2.1 (自定义Host与端口优化版)
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
        # 获取本地版本
        LOCAL_VER=$($XRAY_BIN version | head -n 1 | awk '{print $2}')
        
        # 获取线上最新版本 (屏蔽 grep 错误输出)
        LATEST_VER=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' 2>/dev/null | sed -E 's/.*"v([^"]+)".*/\1/')
        
        # 兼容处理: 如果无法获取线上版本，则仅提示已安装
        if [ -z "$LATEST_VER" ]; then
             echo -e "${GREEN}[+] 系统已安装 Xray 核心！${NC}"
             echo -e "当前本地版本: ${CYAN}v${LOCAL_VER}${NC}"
             echo -e "${YELLOW}提示: 由于网络原因无法获取 GitHub 最新版本信息，跳过更新检查。${NC}"
             read -p "按回车键返回主菜单..." dummy
             return
        fi

        echo -e "${GREEN}[+] 系统已安装 Xray 核心！${NC}"
        echo -e "当前本地版本: ${CYAN}v${LOCAL_VER}${NC}"
        echo -e "线上最新版本: ${CYAN}v${LATEST_VER}${NC}"
        echo -e "--------------------------------------------------"

        if [ "$LOCAL_VER" != "$LATEST_VER" ] && [ -n "$LOCAL_VER" ]; then
            echo -e "${YELLOW}发现新版本！${NC}"
            read -p "是否立刻更新到 v${LATEST_VER}？[y/N]: " CHOOSE_UPDATE
            if [[ ! "$CHOOSE_UPDATE" =~ ^[Yy]$ ]]; then
                echo -e "已取消更新。"
                sleep 1
                return
            fi
        else
            echo -e "${GREEN}当前已是最新版本，无需更新！${NC}"
            read -p "按回车键返回主菜单..." dummy
            return
        fi
    else
        echo -e "${YELLOW}[!] 未检测到 Xray 核心，准备开始全新安装...${NC}"
    fi

    echo -e "${BLUE}[+] 正在调用官方脚本下载核心...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    check_xray_installed
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[+] 核心部署成功！${NC}"
    else
        echo -e "${RED}[-] 核心部署失败！请检查服务器连接 GitHub 的网络状态。${NC}"
    fi
    read -p "按回车键返回主菜单..." dummy
}

# 3. 完全卸载 Xray
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

# 4. 解析并展示当前配置与链接
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
    
    echo -e "${YELLOW}【原始 config.json 内容】${NC}"
    cat "$CONFIG_FILE"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${YELLOW}【解析生成的客户端导入链接】${NC}"

    check_xray_installed

    # 纯 Bash 解析 Reality 链接
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

    # 纯 Bash 解析 VLESS+WS 免流链接
    if grep -q '"network": "ws"' "$CONFIG_FILE"; then
        PORT_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"port"' | tail -n 1 | tr -d -c '0-9')
        UUID_WS=$(grep -B 10 '"network": "ws"' "$CONFIG_FILE" | grep '"id"' | tail -n 1 | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="id") print $(i+2)}')
        
        # 提取自定义 Host
        HOST_NAME=$(grep -A 5 '"wsSettings"' "$CONFIG_FILE" | grep -i '"Host"' | head -n 1 | awk -F'"' '{print $4}')
        HOST_NAME=${HOST_NAME:-"t7z.cupid.iqiyi.com"}
        
        if [ -n "$UUID_WS" ] && [ -n "$PORT_WS" ]; then
            WS_LINK="vless://${UUID_WS}@${SERVER_IP}:${PORT_WS}?path=%2F&security=&encryption=none&host=${HOST_NAME}&type=ws#VLESS_WS_${SERVER_IP}"
            echo -e "${PURPLE}[+] VLESS+WebSocket [免流专用] 链接:${NC}"
            echo -e "${CYAN}${WS_LINK}${NC}"
            echo -e "--------------------------------------------------"
        fi
    fi

    read -p "按回车键返回主菜单..." dummy
}

# 2. 子菜单交互式配置向导
config_xray_flexible() {
    check_xray_installed
    if [ $? -ne 0 ]; then
        echo -e "${RED}警告：系统未能检测到 Xray 核心可执行文件！${NC}"
        echo -e "${YELLOW}请先退回主菜单执行 [选项 1] 安装核心。${NC}"
        read -p "即使核心缺失，仍然强行修改配置文件吗？[y/N]: " FORCE_EDIT
        if [[ ! "$FORCE_EDIT" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}              Xray 协议配置管理器子菜单             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e " 请选择您要配置的协议组合模式："
    echo -e " ${GREEN}1. 仅配置 VLESS-XTLS-Reality (抗封锁推荐)${NC}"
    echo -e " ${GREEN}2. 仅配置 VLESS+WS (免流推荐)${NC}"
    echo -e " ${GREEN}3. 双协议同时配置 (共存模式)${NC}"
    echo -e " 0. 返回主菜单"
    echo -e "${BLUE}==================================================${NC}"
    read -p "请输入选项 [0-3]: " PROTO_CHOICE

    ENABLE_REALITY=false
    ENABLE_WS=false

    case $PROTO_CHOICE in
        1) ENABLE_REALITY=true ;;
        2) ENABLE_WS=true ;;
        3) ENABLE_REALITY=true; ENABLE_WS=true ;;
        0) return ;;
        *) echo -e "${RED}无效输入，返回主菜单。${NC}"; sleep 1; return ;;
    esac

    # 配置 Reality 变量
    if [ "$ENABLE_REALITY" = true ]; then
        echo -e "\n${YELLOW}▶ Reality 端口设置${NC}"
        echo -e "1. 随机自动生成高端口 [10000-65535]\n2. 手动输入自定义端口"
        read -p "请选择 [默认 1]: " REALITY_PORT_CHOICE
        if [ "${REALITY_PORT_CHOICE:-1}" -eq 2 ]; then
            read -p "请输入自定义端口 [回车默认 443]: " PORT_REALITY
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
        read -p "请输入 Reality 伪装目标网站 [回车默认 www.microsoft.com]: " DEST
        DEST=${DEST:-www.microsoft.com}
    fi

    # 配置 WS 变量
    if [ "$ENABLE_WS" = true ]; then
        echo -e "\n${YELLOW}▶ VLESS+WS 端口设置${NC}"
        echo -e "1. 使用免流推荐端口 [80]\n2. 手动输入自定义端口"
        read -p "请选择 [默认 1]: " WS_PORT_CHOICE
        
        ws_port_loop=true
        while [ "$ws_port_loop" = true ]; do
            if [ "${WS_PORT_CHOICE:-1}" -eq 2 ]; then
                read -p "请输入自定义端口 [回车默认 443]: " PORT_WS
                PORT_WS=${PORT_WS:-443}
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

        echo -e "\n${YELLOW}▶ 免流伪装 Host 设置${NC}"
        echo -e "1. 使用默认爱奇艺 Host [t7z.cupid.iqiyi.com]\n2. 手动输入自定义 Host"
        read -p "请选择 [默认 1]: " HOST_CHOICE
        if [ "${HOST_CHOICE:-1}" -eq 2 ]; then
            read -p "请输入自定义免流 Host [回车默认 t7z.cupid.iqiyi.com]: " HOST_NAME
            HOST_NAME=${HOST_NAME:-"t7z.cupid.iqiyi.com"}
        else
            HOST_NAME="t7z.cupid.iqiyi.com"
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
        KEYS=$($XRAY_BIN x25519 2>/dev/null)
        if [ -z "$KEYS" ]; then
            echo -e "${RED}致命错误：找不到 Xray 核心，无法生成 Reality 密钥！请先安装核心。${NC}"
            read -p "按回车键退出..." dummy
            exit 1
        fi
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
            "wsSettings": { 
                "path": "/",
                "headers": {
                    "Host": "$HOST_NAME"
                }
            }
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
    echo -e "${GREEN}    Xray 自动化管理脚本 稳定版 v2.1     ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e " 1. 检查并安装/更新 Xray 核心"
    echo -e " 2. 添加 / 修改协议配置 (Reality/免流)"
    echo -e " 3. 查看当前协议配置与链接"
    echo -e " 4. 一键卸载 Xray 核心及配置"
    echo -e " 0. 退出脚本"
    echo -e "${GREEN}========================================${NC}"
    read -p "请选择操作 [0-4]: " choice

    case $choice in
        1)
            install_xray_core
            ;;
        2)
            config_xray_flexible
            ;;
        3)
            view_current_config
            ;;
        4)
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
