#!/bin/bash

# ==============================================================
# Clash 配置管理神器 (v12.0 维护面板版)
# ==============================================================

# --- 全局配置 ---
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
OUTPUT_FILE="/root/clash_final.yaml"
PORT_REALITY=443
PORT_TLS=8443

# --- 颜色定义 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# --- 辅助函数 ---
function print_title() { echo -e "\n${PURPLE}${BOLD}>> $1${PLAIN}"; }
function print_step() { echo -e "${BLUE}➜  $1${PLAIN}"; }
function print_success() { echo -e "${GREEN}✔  $1${PLAIN}"; }
function print_error() { echo -e "${RED}✖  $1${PLAIN}"; }

# ===========================================
# 核心功能模块 (封装成函数以便调用)
# ===========================================

# 1. 初始化环境
function init_env() {
    rm -f *.tmp vmess_parser.py
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠️  警告: 未检测到 Python3${PLAIN}"
    fi
    # 生成 Python 解析器 (顶格输出)
    cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse
def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        return f"""- name: "{data.get('ps', 'Imported-VMess')}"\n  type: vmess\n  server: {data.get('add')}\n  port: {data.get('port')}\n  uuid: {data.get('id')}\n  alterId: {data.get('aid', 0)}\n  cipher: {data.get('scy', 'auto')}\n  udp: true\n  tls: {str(data.get('tls', '') == 'tls').lower()}\n  network: {data.get('net', 'tcp')}\n  servername: {data.get('host', '') or data.get('sni', '')}\n  ws-opts:\n    path: {data.get('path', '/')}\n    headers:\n      Host: {data.get('host', '') or data.get('sni', '')}\n"""
    except:
        try:
            if "?" in b64_body: b64, query = b64_body.split("?", 1)
            else: b64, query = b64_body, ""
            pad = len(b64) % 4
            if pad: b64 += '=' * (4 - pad)
            decoded = base64.b64decode(b64).decode('utf-8')
            user_info, host_info = decoded.split('@')
            uuid = user_info.split(':')[1]
            server, port = host_info.split(':')
            params = dict(urllib.parse.parse_qsl(query))
            name = params.get('remarks', 'Imported-VMess')
            net = params.get('obfs', 'tcp')
            if net == 'websocket': net = 'ws'
            tls = 'true' if params.get('tls') == '1' else 'false'
            host = params.get('obfsParam') or params.get('peer') or server
            path = params.get('path', '/')
            return f"""- name: "{name}"\n  type: vmess\n  server: {server}\n  port: {port}\n  uuid: {uuid}\n  alterId: {params.get('alterId', 0)}\n  cipher: auto\n  udp: true\n  tls: {tls}\n  network: {net}\n  servername: {host}\n  ws-opts:\n    path: {path}\n    headers:\n      Host: {host}\n"""
        except: return None
if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
EOF
}

# 2. 下载模板
function download_template() {
    print_step "正在下载最新模板..."
    curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"
    if ! grep -q "proxies:" template.tmp; then
        print_error "模板下载失败"
        exit 1
    else
        print_success "模板已更新"
    fi
}

# 3. 生成流程 (主逻辑)
function run_generator() {
    init_env
    download_template

    # --- 机场订阅 ---
    print_title "📡 机场订阅设置"
    providers_yaml=""
    group_use_yaml=""
    count=0

    while true; do
        if [ $count -eq 0 ]; then read -p "$(echo -e "${YELLOW}❓ 是否添加机场订阅？[y/n]: ${PLAIN}")" add_sub
        else read -p "$(echo -e "${YELLOW}❓ 继续添加？[y/n]: ${PLAIN}")" add_sub; fi
        [[ "$add_sub" != "y" && "$add_sub" != "Y" ]] && break

        echo -e "${GREEN}➜ 粘贴地址:${PLAIN}"
        read -r sub_url
        if [[ -n "$sub_url" ]]; then
            count=$((count+1))
            p_name="Airport_${count}"
            echo -e "${GREEN}   ✔ 已记录: ${p_name}${PLAIN}"
            providers_yaml="${providers_yaml}  ${p_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
            group_use_yaml="${group_use_yaml}      - ${p_name}\n"
        fi
    done

    if [ $count -gt 0 ]; then
        sed -i '/^  Airport:/,+8d' template.tmp
        sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
        sed -i '/- Airport/d' template.tmp
        sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
    fi

    # --- 本机节点 ---
    print_title "🏠 本机节点生成"
    AUTO_NODES_TEMP="auto_nodes.tmp"
    echo "" > "$AUTO_NODES_TEMP"
    if [ -f "$INFO_FILE" ]; then
        source "$INFO_FILE"
        IP=$(curl -s https://api.ipify.org)
        cat << EOF >> "$AUTO_NODES_TEMP"
- name: ElJefe_Reality
  type: vless
  server: $IP
  port: $PORT_REALITY
  uuid: $UUID
  network: tcp
  tls: true
  udp: true
  flow: xtls-rprx-vision
  servername: $SNI
  reality-opts:
    public-key: $PUB_KEY
    short-id: "$SID"
  client-fingerprint: chrome

EOF
        if [[ -n "$DOMAIN" ]]; then
            cat << EOF >> "$AUTO_NODES_TEMP"
- name: ElJefe_VLESS_CDN
  type: vless
  server: $DOMAIN
  port: $PORT_TLS
  uuid: $UUID
  udp: true
  tls: true
  network: ws
  servername: $DOMAIN
  skip-cert-verify: false
  ws-opts:
    path: /vless
    headers:
      Host: $DOMAIN

- name: ElJefe_VMess_CDN
  type: vmess
  server: $DOMAIN
  port: $PORT_TLS
  uuid: $UUID
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $DOMAIN
  ws-opts:
    path: /vmess
    headers:
      Host: $DOMAIN

EOF
        fi
        print_success "本机节点已生成"
    else
        echo -e "${YELLOW}⚠️  未找到本机配置${PLAIN}"
    fi

    # --- 手动节点 ---
    print_title "🛠️  手动节点处理"
    MANUAL_NODES_TEMP="manual_nodes.tmp"
    echo "" > "$MANUAL_NODES_TEMP"

    if [ -s "$MANUAL_NODES_FILE" ]; then
        # 智能计数
        COUNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")
        echo -e "${CYAN}ℹ️  正在处理 ${COUNT} 个手动节点...${PLAIN}"
        
        while read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^#.*$ ]] && continue
            
            if [[ "$line" == vmess://* ]]; then
                RESULT=$(python3 vmess_parser.py "$line")
                [[ -n "$RESULT" ]] && echo "$RESULT" >> "$MANUAL_NODES_TEMP" && echo "" >> "$MANUAL_NODES_TEMP"
            else
                echo "$line" >> "$MANUAL_NODES_TEMP"
            fi
        done < "$MANUAL_NODES_FILE"
        print_success "处理完成"
    else
        echo -e "${CYAN}ℹ️  无手动节点${PLAIN}"
    fi

    # --- 拼接 ---
    print_step "正在写入文件..."
    NODE_NAMES=""
    for temp_file in "$AUTO_NODES_TEMP" "$MANUAL_NODES_TEMP"; do
        if [ -s "$temp_file" ]; then
            while read -r line; do
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name: ]]; then
                    NAME=$(echo "$line" | awk -F'name: ' '{print $2}' | tr -d '"' | tr -d "'" | sed 's/^[ \t]*//;s/[ \t]*$//')
                    [[ -n "$NAME" ]] && NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
                fi
            done < "$temp_file"
        fi
    done

    [[ -s "$AUTO_NODES_TEMP" ]] && sed -i '/#VAR_AUTO_NODES#/r auto_nodes.tmp' template.tmp
    sed -i '/#VAR_AUTO_NODES#/d' template.tmp

    [[ -s "$MANUAL_NODES_TEMP" ]] && sed -i '/#VAR_MANUAL_NODES#/r manual_nodes.tmp' template.tmp
    sed -i '/#VAR_MANUAL_NODES#/d' template.tmp

    if [[ -n "$NODE_NAMES" ]]; then
        echo -e "$NODE_NAMES" > node_names.tmp
        sed -i '/#VAR_ALL_NODE_NAMES#/r node_names.tmp' template.tmp
        rm -f node_names.tmp
    fi
    sed -i '/#VAR_ALL_NODE_NAMES#/d' template.tmp

    mv template.tmp "$OUTPUT_FILE"
    chmod 644 "$OUTPUT_FILE"
    rm -f auto_nodes.tmp manual_nodes.tmp vmess_parser.py
    
    echo ""
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e " 📂 ${BOLD}配置已生成:${PLAIN} ${CYAN}${OUTPUT_FILE}${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
}

# ===========================================
# 菜单功能
# ===========================================

function menu_add_manual() {
    echo ""
    print_title "➕ 添加手动节点"
    echo -e "${GREEN}➜ 请粘贴链接 (vmess://...):${PLAIN}"
    read -r link
    if [[ -n "$link" ]]; then
        if [ ! -f "$MANUAL_NODES_FILE" ]; then touch "$MANUAL_NODES_FILE"; fi
        echo "$link" >> "$MANUAL_NODES_FILE"
        print_success "节点已添加到数据库，请运行 [1] 重新生成配置以生效。"
    else
        print_error "输入为空"
    fi
}

function menu_clear_manual() {
    echo ""
    read -p "$(echo -e "${RED}❓ 确定清空所有手动节点吗？[y/n]: ${PLAIN}")" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
        print_success "手动节点已清空，请运行 [1] 重新生成配置。"
    fi
}

function menu_reset_all() {
    echo ""
    read -p "$(echo -e "${RED}⚠️  警告: 将删除所有配置文件、手动节点记录。确定？[y/n]: ${PLAIN}")" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -f "$OUTPUT_FILE" "$MANUAL_NODES_FILE"
        print_success "所有数据已清除。下次运行将进入初始化向导。"
        exit 0
    fi
}

function show_menu() {
    clear
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e "${BOLD}   Clash 配置管理面板 ${PLAIN}${CYAN}v12.0${PLAIN}"
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 🔄 重新生成配置文件 (刷新订阅/模板)"
    echo -e "${GREEN}2.${PLAIN} ➕ 添加手动节点 (VMess/VLESS)"
    echo -e "${GREEN}3.${PLAIN} 🗑️  清空手动节点"
    echo -e "${GREEN}4.${PLAIN} 📄 查看当前配置内容"
    echo -e "${RED}5.${PLAIN} 🧹 删除所有配置 (重置)"
    echo -e "${GREEN}0.${PLAIN} 🚪 退出脚本"
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e "当前配置: ${CYAN}${OUTPUT_FILE}${PLAIN}"
    if [ -f "$MANUAL_NODES_FILE" ]; then
        CNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")
        echo -e "手动节点: ${YELLOW}${CNT} 个${PLAIN}"
    else
        echo -e "手动节点: ${YELLOW}0 个${PLAIN}"
    fi
    echo ""
    read -p "请输入选项 [0-5]: " choice
    
    case "$choice" in
        1) run_generator ;;
        2) menu_add_manual; read -p "按回车返回..." ;;
        3) menu_clear_manual; read -p "按回车返回..." ;;
        4) cat "$OUTPUT_FILE"; read -p "按回车返回..." ;;
        5) menu_reset_all ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}"; sleep 1 ;;
    esac
}

# ===========================================
# 主程序入口
# ===========================================

if [ ! -f "$OUTPUT_FILE" ]; then
    # === 首次运行模式 ===
    clear
    print_title "🚀 欢迎使用 Clash 配置向导 (首次运行)"
    
    # 首次运行先问手动节点
    if [ ! -f "$MANUAL_NODES_FILE" ]; then touch "$MANUAL_NODES_FILE"; fi
    read -p "$(echo -e "${YELLOW}❓ 是否先添加一个手动节点？[y/n]: ${PLAIN}")" first_add
    if [[ "$first_add" == "y" || "$first_add" == "Y" ]]; then
        echo -e "${GREEN}➜ 粘贴链接:${PLAIN}"
        read -r link
        [[ -n "$link" ]] && echo "$link" >> "$MANUAL_NODES_FILE"
    fi
    
    run_generator
else
    # === 维护面板模式 ===
    while true; do
        show_menu
    done
fi
