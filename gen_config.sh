#!/bin/bash

# ==============================================================
# Clash 配置管理神器 (v13.4 - UI对齐修复版)
# ==============================================================

# --- 全局配置 ---
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
AIRPORT_URLS_FILE="/root/airport_urls.txt"
OUTPUT_FILE="/root/clash_final.yaml"
LOCAL_NAME_FILE="/root/local_node_name.txt"
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
# 核心功能模块
# ===========================================

function init_env() {
    rm -f *.tmp vmess_parser.py
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠️  警告: 未检测到 Python3${PLAIN}"
    fi
    # Python 解析脚本
    cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse

def parse_vmess(link, custom_name=None):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        node_name = custom_name if custom_name else data.get('ps', 'Imported-VMess')
        return f"""- name: "{node_name}"\n  type: vmess\n  server: {data.get('add')}\n  port: {data.get('port')}\n  uuid: {data.get('id')}\n  alterId: {data.get('aid', 0)}\n  cipher: {data.get('scy', 'auto')}\n  udp: true\n  tls: {str(data.get('tls', '') == 'tls').lower()}\n  network: {data.get('net', 'tcp')}\n  servername: {data.get('host', '') or data.get('sni', '')}\n  ws-opts:\n    path: {data.get('path', '/')}\n    headers:\n      Host: {data.get('host', '') or data.get('sni', '')}\n"""
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
            name = custom_name if custom_name else params.get('remarks', 'Imported-VMess')
            net = params.get('obfs', 'tcp')
            if net == 'websocket': net = 'ws'
            tls = 'true' if params.get('tls') == '1' else 'false'
            host = params.get('obfsParam') or params.get('peer') or server
            path = params.get('path', '/')
            return f"""- name: "{name}"\n  type: vmess\n  server: {server}\n  port: {port}\n  uuid: {uuid}\n  alterId: {params.get('alterId', 0)}\n  cipher: auto\n  udp: true\n  tls: {tls}\n  network: {net}\n  servername: {host}\n  ws-opts:\n    path: {path}\n    headers:\n      Host: {host}\n"""
        except: return None

def parse_vless(link, custom_name=None):
    if not link.startswith("vless://"): return None
    try:
        body = link[8:]
        if "#" in body:
            main_part, original_name = body.split("#", 1)
            original_name = urllib.parse.unquote(original_name).strip()
        else:
            main_part, original_name = body, "Imported-VLESS"
        
        name = custom_name if custom_name else original_name
            
        if "?" in main_part:
            user_host, query = main_part.split("?", 1)
            params = dict(urllib.parse.parse_qsl(query))
        else:
            user_host, query, params = main_part, "", {}

        if "@" in user_host:
            uuid, host_port = user_host.split("@", 1)
        else:
            return None 

        if ":" in host_port:
            if "]:" in host_port:
                server, port = host_port.rsplit(":", 1)
                server = server.replace("[", "").replace("]", "")
            else:
                server, port = host_port.split(":", 1)
        else:
            return None

        type_net = params.get("type", "tcp")
        security = params.get("security", "none")
        flow = params.get("flow", "")
        sni = params.get("sni", "")
        pbk = params.get("pbk", "")
        sid = params.get("sid", "")
        fp = params.get("fp", "chrome")
        path = params.get("path", "/")
        host = params.get("host", "")
        service_name = params.get("serviceName", "")

        yaml_str = f'- name: "{name}"\n  type: vless\n  server: {server}\n  port: {port}\n  uuid: {uuid}\n  udp: true\n  tls: {str(security != "none").lower()}\n  network: {type_net}\n'
        
        if flow: yaml_str += f'  flow: {flow}\n'
        if sni: yaml_str += f'  servername: {sni}\n'
        
        if security == "reality":
            yaml_str += f'  reality-opts:\n    public-key: {pbk}\n    short-id: "{sid}"\n  client-fingerprint: {fp}\n'
        elif security == "tls":
            yaml_str += f'  skip-cert-verify: true\n'
            
        if type_net == "ws":
             yaml_str += f'  ws-opts:\n    path: {path}\n    headers:\n      Host: {host if host else sni}\n'
        elif type_net == "grpc":
             yaml_str += f'  grpc-opts:\n    grpc-service-name: {service_name}\n'
        
        return yaml_str
    except Exception as e:
        return None

if __name__ == "__main__":
    if len(sys.argv) > 1:
        link = sys.argv[1].strip()
        custom_name = None
        if len(sys.argv) > 2:
            arg2 = sys.argv[2].strip()
            if arg2: custom_name = arg2

        res = None
        if link.startswith("vmess://"):
            res = parse_vmess(link, custom_name)
        elif link.startswith("vless://"):
            res = parse_vless(link, custom_name)
        
        if res: print(res)
EOF
}

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

function run_generator() {
    init_env
    download_template

    print_title "📡 机场订阅处理"
    providers_yaml=""
    group_use_yaml=""
    count=0

    if [ -f "$AIRPORT_URLS_FILE" ]; then
        while read -r saved_url; do
            [[ -z "$saved_url" ]] && continue
            count=$((count+1))
            p_name="Airport_${count}"
            echo -e "${GREEN}   ✔ 加载订阅: ${p_name}${PLAIN}"
            providers_yaml="${providers_yaml}  ${p_name}:\n    type: http\n    url: \"${saved_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
            group_use_yaml="${group_use_yaml}      - ${p_name}\n"
        done < "$AIRPORT_URLS_FILE"
    fi

    while true; do
        if [ $count -eq 0 ]; then 
            read -p "$(echo -e "${YELLOW}❓ 未找到订阅，添加？[y/n]: ${PLAIN}")" add_sub
        else 
            read -p "$(echo -e "${YELLOW}❓ 添加临时订阅？[y/n]: ${PLAIN}")" add_sub
        fi
        [[ "$add_sub" != "y" && "$add_sub" != "Y" ]] && break
        echo -e "${GREEN}➜ 粘贴地址:${PLAIN}"
        read -r sub_url
        if [[ -n "$sub_url" ]]; then
            count=$((count+1))
            p_name="Airport_${count}"
            echo -e "${GREEN}   ✔ 已添加临时: ${p_name}${PLAIN}"
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

    print_title "🏠 本机节点生成"
    AUTO_NODES_TEMP="auto_nodes.tmp"
    echo "" > "$AUTO_NODES_TEMP"
    
    # --- 获取本机节点自定义名称前缀 ---
    LOCAL_PREFIX="ElJefe"
    if [ -f "$LOCAL_NAME_FILE" ]; then
        READ_NAME=$(cat "$LOCAL_NAME_FILE" | tr -d '\n')
        [[ -n "$READ_NAME" ]] && LOCAL_PREFIX="$READ_NAME"
    fi
    # -------------------------------

    if [ -f "$INFO_FILE" ]; then
        source "$INFO_FILE"
        IP=$(curl -s https://api.ipify.org)
        cat << EOF >> "$AUTO_NODES_TEMP"
- name: ${LOCAL_PREFIX}_Reality
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
- name: ${LOCAL_PREFIX}_VLESS_CDN
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

- name: ${LOCAL_PREFIX}_VMess_CDN
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
        print_success "本机节点已生成 (前缀: ${LOCAL_PREFIX})"
    else
        echo -e "${YELLOW}⚠️  未找到本机配置${PLAIN}"
    fi

    print_title "🛠️  手动节点处理"
    MANUAL_NODES_TEMP="manual_nodes.tmp"
    echo "" > "$MANUAL_NODES_TEMP"
    if [ -s "$MANUAL_NODES_FILE" ]; then
        COUNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")
        echo -e "${CYAN}ℹ️  正在处理 ${COUNT} 个手动节点...${PLAIN}"
        while read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^#.*$ ]] && continue
            
            read -r link_url custom_name <<< "$line"
            
            if [[ "$link_url" == vmess://* || "$link_url" == vless://* ]]; then
                RESULT=$(python3 vmess_parser.py "$link_url" "$custom_name")
                [[ -n "$RESULT" ]] && echo "$RESULT" >> "$MANUAL_NODES_TEMP" && echo "" >> "$MANUAL_NODES_TEMP"
            else
                echo "$line" >> "$MANUAL_NODES_TEMP"
            fi
            
        done < "$MANUAL_NODES_FILE"
        print_success "处理完成"
    else
        echo -e "${CYAN}ℹ️  无手动节点${PLAIN}"
    fi

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

function menu_add_airport() {
    echo ""
    print_title "✈️  添加机场订阅"
    echo -e "${GREEN}➜ 粘贴地址 (http...):${PLAIN}"
    read -r link
    if [[ -n "$link" ]]; then
        [ ! -f "$AIRPORT_URLS_FILE" ] && touch "$AIRPORT_URLS_FILE"
        echo "$link" >> "$AIRPORT_URLS_FILE"
        print_success "订阅已保存，运行 [1] 生效。"
    else
        print_error "输入为空"
    fi
}

function menu_add_manual() {
    echo ""
    print_title "➕ 添加手动节点"
    echo -e "${GREEN}1. 粘贴链接 (vmess://... 或 vless://...):${PLAIN}"
    read -r link
    
    if [[ -n "$link" ]]; then
        echo -e "${GREEN}2. 给节点起个名字 (留空则使用默认):${PLAIN}"
        read -r node_name
        
        [ ! -f "$MANUAL_NODES_FILE" ] && touch "$MANUAL_NODES_FILE"
        
        if [[ -n "$node_name" ]]; then
            echo "$link $node_name" >> "$MANUAL_NODES_FILE"
            print_success "节点 [$node_name] 已保存！"
        else
            echo "$link" >> "$MANUAL_NODES_FILE"
            print_success "节点已保存（使用默认名）。"
        fi
        echo -e "${CYAN}👉 记得运行选项 [1] 重新生成配置生效。${PLAIN}"
    else
        print_error "输入为空"
    fi
}

function menu_clear_data() {
    echo ""
    echo -e "${YELLOW}请选择要清空的数据:${PLAIN}"
    echo -e " 1. 清空手动节点"
    echo -e " 2. 清空机场订阅"
    echo -e " 0. 取消"
    read -p "请输入: " sub_choice
    case "$sub_choice" in
        1) echo "" > "$MANUAL_NODES_FILE"; print_success "手动节点已清空。";;
        2) echo "" > "$AIRPORT_URLS_FILE"; print_success "机场订阅已清空。";;
        *) echo "取消" ;;
    esac
}

function menu_reset_all() {
    echo ""
    read -p "$(echo -e "${RED}⚠️  删除所有配置？[y/n]: ${PLAIN}")" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -f "$OUTPUT_FILE" "$MANUAL_NODES_FILE" "$AIRPORT_URLS_FILE" "$LOCAL_NAME_FILE"
        print_success "已重置。"
        exit 0
    fi
}

# --- 节点重命名管理 ---
function menu_rename_local() {
    print_title "🏠 重命名本机节点"
    CUR_NAME="ElJefe"
    [ -f "$LOCAL_NAME_FILE" ] && CUR_NAME=$(cat "$LOCAL_NAME_FILE")
    
    echo -e "当前本机节点前缀: ${YELLOW}${CUR_NAME}${PLAIN}"
    echo -e "生成后效果: ${CUR_NAME}_Reality / ${CUR_NAME}_CDN"
    echo ""
    echo -e "${GREEN}➜ 请输入新的节点前缀 (例如 US_Node):${PLAIN}"
    read -r new_name
    if [[ -n "$new_name" ]]; then
        echo "$new_name" > "$LOCAL_NAME_FILE"
        print_success "已修改为: $new_name"
        echo -e "${CYAN}👉 请运行 [1] 重新生成配置以生效。${PLAIN}"
    else
        echo "未修改。"
    fi
}

function menu_rename_manual() {
    print_title "✏️  重命名手动节点"
    if [ ! -s "$MANUAL_NODES_FILE" ]; then
        print_error "没有找到手动节点文件。"
        return
    fi

    # 读取文件到数组
    mapfile -t lines < "$MANUAL_NODES_FILE"
    
    if [ ${#lines[@]} -eq 0 ]; then
         print_error "节点列表为空。"
         return
    fi

    echo -e "${YELLOW}请选择要重命名的节点:${PLAIN}"
    i=0
    valid_indices=()
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        # 解析展示
        read -r link name <<< "$line"
        if [[ -z "$name" ]]; then name="(默认名称)"; fi
        # 截取link前20个字符用于展示
        short_link="${link:0:20}..."
        echo -e " [${i}] 名称: ${CYAN}${name}${PLAIN} \t链接: ${short_link}"
        valid_indices+=($i)
        i=$((i+1))
    done

    echo ""
    read -p "请输入序号 (0-$((i-1))): " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge "$i" ]; then
        print_error "无效序号"
        return
    fi

    selected_line="${lines[$choice]}"
    read -r link old_name <<< "$selected_line"
    
    echo -e "当前名称: ${YELLOW}${old_name:-默认}${PLAIN}"
    echo -e "${GREEN}➜ 请输入新名称 (不要包含空格):${PLAIN}"
    read -r new_input_name
    
    if [[ -n "$new_input_name" ]]; then
        lines[$choice]="$link $new_input_name"
        printf "%s\n" "${lines[@]}" > "$MANUAL_NODES_FILE"
        print_success "名称已更新！"
        echo -e "${CYAN}👉 请运行 [1] 重新生成配置以生效。${PLAIN}"
    else
        echo "未修改。"
    fi
}

function menu_manage_names() {
    clear
    print_title "🏷️  节点名称管理中心"
    echo -e " 1. 修改 ${YELLOW}本机节点${PLAIN} 前缀 (当前: $(cat "$LOCAL_NAME_FILE" 2>/dev/null || echo "ElJefe"))"
    echo -e " 2. 修改 ${YELLOW}手动节点${PLAIN} 名称"
    echo -e " 0. 返回主菜单"
    echo ""
    read -p "请输入选项: " nc
    case "$nc" in
        1) menu_rename_local; read -p "按回车继续..." ;;
        2) menu_rename_manual; read -p "按回车继续..." ;;
        *) return ;;
    esac
}
# ---------------------------

function show_menu() {
    clear
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e "${BOLD}   Clash 配置管理面板 ${PLAIN}${CYAN}v13.4${PLAIN}"
    echo -e "${PURPLE}==============================================${PLAIN}"
    
    # 计数
    AIR_CNT=0; MAN_CNT=0
    [ -f "$AIRPORT_URLS_FILE" ] && AIR_CNT=$(grep -cve '^\s*$' "$AIRPORT_URLS_FILE")
    [ -f "$MANUAL_NODES_FILE" ] && MAN_CNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")

    # [修复] 使用 %-4s 为图标列预留固定宽度，确保对齐
    printf "${GREEN} 1.${PLAIN}  %-4s %s\n" "🔄" "重新生成配置 (加载所有数据)"
    printf "${GREEN} 2.${PLAIN}  %-4s %s [当前: ${YELLOW}%s${PLAIN}]\n" "✈️" "添加机场订阅" "$AIR_CNT"
    printf "${GREEN} 3.${PLAIN}  %-4s %s [当前: ${YELLOW}%s${PLAIN}]\n" "➕" "添加手动节点" "$MAN_CNT"
    printf "${GREEN} 4.${PLAIN}  %-4s %s\n" "🗑️" "清空数据 (节点/订阅)"
    printf "${GREEN} 5.${PLAIN}  %-4s %s\n" "📄" "查看配置文件"
    printf "${BLUE} 7.${PLAIN}  %-4s %s\n" "✏️" "重命名节点 (本机/手动)"
    printf "${RED} 6.${PLAIN}  %-4s %s\n" "🧹" "重置所有数据 (删库)"
    printf "${GREEN} 0.${PLAIN}  %-4s %s\n" "🚪" "退出"
    
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e " 📂 输出路径: ${CYAN}${OUTPUT_FILE}${PLAIN}"
    echo ""
    read -p " 请输入选项 [0-7]: " choice
    
    case "$choice" in
        1) run_generator; read -p "按回车继续..." ;;
        2) menu_add_airport; read -p "按回车继续..." ;;
        3) menu_add_manual; read -p "按回车继续..." ;;
        4) menu_clear_data; read -p "按回车继续..." ;;
        5) echo ""; cat "$OUTPUT_FILE"; echo ""; read -p "按回车继续..." ;;
        6) menu_reset_all ;;
        7) menu_manage_names ;; 
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}"; sleep 1 ;;
    esac
}

# ===========================================
# 主入口
# ===========================================

if [ ! -f "$OUTPUT_FILE" ]; then
    clear
    print_title "🚀 欢迎使用 Clash 配置向导 (首次运行)"
    
    # 引导添加机场
    if [ ! -f "$AIRPORT_URLS_FILE" ]; then touch "$AIRPORT_URLS_FILE"; fi
    read -p "$(echo -e "${YELLOW}❓ 是否添加机场订阅？[y/n]: ${PLAIN}")" first_air
    if [[ "$first_air" == "y" || "$first_air" == "Y" ]]; then
        echo -e "${GREEN}➜ 粘贴地址:${PLAIN}"
        read -r link
        [[ -n "$link" ]] && echo "$link" >> "$AIRPORT_URLS_FILE"
    fi

    # 引导添加手动节点
    if [ ! -f "$MANUAL_NODES_FILE" ]; then touch "$MANUAL_NODES_FILE"; fi
    read -p "$(echo -e "${YELLOW}❓ 是否添加手动节点？[y/n]: ${PLAIN}")" first_node
    if [[ "$first_node" == "y" || "$first_node" == "Y" ]]; then
        echo -e "${GREEN}➜ 粘贴链接:${PLAIN}"
        read -r link
        [[ -n "$link" ]] && echo "$link" >> "$MANUAL_NODES_FILE"
    fi
    
    run_generator
    
    echo -e "\n${CYAN}👉 提示: 再次运行此脚本即可进入管理维护面板。${PLAIN}"
else
    while true; do
        show_menu
    done
fi
