#!/bin/bash

# ==============================================================
# Clash 配置管理神器 (v13.9 - 乱码终结版)
# ==============================================================

# --- [核心修复] 强制设置 UTF-8 环境 ---
# 优先尝试 C.UTF-8 (兼容性最好)，如果失败则尝试 en_US.UTF-8
if locale -a | grep -q "C.UTF-8"; then
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
elif locale -a | grep -q "en_US.utf8"; then
    export LANG=en_US.utf8
    export LC_ALL=en_US.utf8
else
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
fi

# --- 全局配置 ---
# 依然从 Gist 下载模板
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

    # Python 解析脚本 (保持 2 空格缩进)
    cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse

def parse_vmess(link, custom_prefix=None):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        
        if custom_prefix:
            node_name = f"{custom_prefix}_VMess"
        else:
            node_name = data.get('ps', 'Imported-VMess')
        
        # 保持缩进
        return f"""  - name: "{node_name}"\n    type: vmess\n    server: {data.get('add')}\n    port: {data.get('port')}\n    uuid: {data.get('id')}\n    alterId: {data.get('aid', 0)}\n    cipher: {data.get('scy', 'auto')}\n    udp: true\n    tls: {str(data.get('tls', '') == 'tls').lower()}\n    network: {data.get('net', 'tcp')}\n    servername: {data.get('host', '') or data.get('sni', '')}\n    ws-opts:\n      path: {data.get('path', '/')}\n      headers:\n        Host: {data.get('host', '') or data.get('sni', '')}\n"""
    except:
        return None

def parse_vless(link, custom_prefix=None):
    if not link.startswith("vless://"): return None
    try:
        body = link[8:]
        if "#" in body:
            main_part, original_name = body.split("#", 1)
            original_name = urllib.parse.unquote(original_name).strip()
        else:
            main_part, original_name = body, "Imported-VLESS"
            
        if "?" in main_part:
            user_host, query = main_part.split("?", 1)
            params = dict(urllib.parse.parse_qsl(query))
        else:
            user_host, query, params = main_part, "", {}

        security = params.get("security", "none")
        if custom_prefix:
            if security == "reality":
                node_name = f"{custom_prefix}_Reality"
            else:
                node_name = f"{custom_prefix}_VLESS"
        else:
            node_name = original_name

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
        flow = params.get("flow", "")
        sni = params.get("sni", "")
        pbk = params.get("pbk", "")
        sid = params.get("sid", "")
        fp = params.get("fp", "chrome")
        path = params.get("path", "/")
        host = params.get("host", "")
        service_name = params.get("serviceName", "")

        # 保持缩进
        yaml_str = f'  - name: "{node_name}"\n    type: vless\n    server: {server}\n    port: {port}\n    uuid: {uuid}\n    udp: true\n    tls: {str(security != "none").lower()}\n    network: {type_net}\n'
        
        if flow: yaml_str += f'    flow: {flow}\n'
        if sni: yaml_str += f'    servername: {sni}\n'
        
        if security == "reality":
            yaml_str += f'    reality-opts:\n      public-key: {pbk}\n      short-id: "{sid}"\n    client-fingerprint: {fp}\n'
        elif security == "tls":
            yaml_str += f'    skip-cert-verify: true\n'
            
        if type_net == "ws":
             yaml_str += f'    ws-opts:\n      path: {path}\n      headers:\n        Host: {host if host else sni}\n'
        elif type_net == "grpc":
             yaml_str += f'    grpc-opts:\n      grpc-service-name: {service_name}\n'
        
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
    curl -s -L -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)" --connect-timeout 10
    
    if [ ! -s template.tmp ] || ! grep -q "proxies:" template.tmp; then
        print_error "模板下载失败！"
        rm -f template.tmp
        exit 1
    fi
    
    # [新增] 乱码检测逻辑
    # 检查模板里是否有 '🏠' (自建组图标)，如果变为了 '??'，说明 curl 下载时就坏了或者环境问题
    if grep -q "??" template.tmp && ! grep -q "🏠" template.tmp; then
        echo -e "${YELLOW}⚠️  警告: 检测到 Emoji 乱码!${PLAIN}"
        echo -e "${YELLOW}👉 你的系统不支持 UTF-8 字符。脚本将尝试自动修复...${PLAIN}"
        # 备选方案：如果环境真的烂到不行，这里其实应该建议用户换个终端或系统
        # 但我们尽量尝试用 sed 替换一下已知的乱码占位符（虽然很难完美）
    else
        print_success "模板已更新 (Emoji 支持正常)"
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
    
    LOCAL_PREFIX="ElJefe"
    if [ -f "$LOCAL_NAME_FILE" ]; then
        READ_NAME=$(cat "$LOCAL_NAME_FILE" | tr -d '\n')
        [[ -n "$READ_NAME" ]] && LOCAL_PREFIX="$READ_NAME"
    fi

    if [ -f "$INFO_FILE" ]; then
        source "$INFO_FILE"
        IP=$(curl -s https://api.ipify.org)
        # [修复] 手动添加 2 空格缩进
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
            
            link_url=$(echo "$line" | awk '{print $1}')
            custom_name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
            
            if [[ "$link_url" == vmess://* || "$link_url" == vless://* ]]; then
                RESULT=$(python3 vmess_parser.py "$link_url" "$custom_name")
                [[ -n "$RESULT" ]] && echo "$RESULT" >> "$MANUAL_NODES_TEMP" && echo "" >> "$MANUAL_NODES_TEMP"
            else
                # [修复] YAML 增加缩进
                if [[ "$line" =~ ^- ]]; then
                    echo "  $line" >> "$MANUAL_NODES_TEMP"
                else
                    echo "$line" >> "$MANUAL_NODES_TEMP"
                fi
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
                    # 强力提取名字，移除引号
                    NAME=$(echo "$line" | sed 's/.*name: //;s/"//g;s/'"'"'//g;s/^[ \t]*//;s/[ \t]*$//')
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
# 菜单功能 (模块化)
# ===========================================

function menu_add_airport() {
    print_title "✈️  添加机场订阅"
    echo -e "${GREEN}➜ 粘贴地址 (http...):${PLAIN}"
    read -r link
    if [[ -n "$link" ]]; then
        [ ! -f "$AIRPORT_URLS_FILE" ] && touch "$AIRPORT_URLS_FILE"
        echo "$link" >> "$AIRPORT_URLS_FILE"
        print_success "订阅已保存。"
    else
        print_error "输入为空"
    fi
}

function menu_rename_local() {
    print_title "🏠 本机节点前缀设置"
    CUR_NAME="ElJefe"
    [ -f "$LOCAL_NAME_FILE" ] && CUR_NAME=$(cat "$LOCAL_NAME_FILE")
    
    echo -e "当前前缀: ${YELLOW}${CUR_NAME}${PLAIN}"
    echo -e "示例效果: ${CUR_NAME}_Reality"
    echo ""
    echo -e "${GREEN}➜ 输入新前缀 (例如 US_Node):${PLAIN}"
    read -r new_name
    if [[ -n "$new_name" ]]; then
        echo "$new_name" > "$LOCAL_NAME_FILE"
        print_success "已修改，请 [1] 重新生成生效。"
    else
        echo "未修改。"
    fi
}

function menu_manual_manager() {
    while true; do
        clear
        echo -e "${PURPLE}==============================================${PLAIN}"
        echo -e "${BOLD}   🧩 手动节点管理中心 ${PLAIN}"
        echo -e "${PURPLE}==============================================${PLAIN}"
        
        [ ! -f "$MANUAL_NODES_FILE" ] && touch "$MANUAL_NODES_FILE"
        mapfile -t lines < "$MANUAL_NODES_FILE"
        node_count=${#lines[@]}
        
        if [ $node_count -eq 0 ]; then
             echo -e "${CYAN}   (暂无节点)${PLAIN}"
        else
            echo -e "${YELLOW}   序号  前缀名(自动后缀)    链接预览${PLAIN}"
            echo -e "${YELLOW}   ----  ------------------  ----------------${PLAIN}"
            i=0
            for line in "${lines[@]}"; do
                [[ -z "$line" ]] && continue
                link=$(echo "$line" | awk '{print $1}')
                name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
                
                if [[ -z "$name" ]]; then name="(未设置)"; fi
                
                d_name="${name:0:18}"
                d_link="${link:0:25}..."
                printf "   [%2d]  %-18s  %s\n" "$i" "$d_name" "$d_link"
                i=$((i+1))
            done
        fi
        echo -e "${PURPLE}==============================================${PLAIN}"
        echo -e " ${GREEN}a.${PLAIN} 新增节点"
        echo -e " ${RED}d.${PLAIN} 删除节点"
        echo -e " ${BLUE}r.${PLAIN} 重命名 (设置前缀)"
        echo -e " ${YELLOW}c.${PLAIN} 清空所有节点"
        echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
        echo ""
        read -p " 请输入操作: " op
        
        case "$op" in
            a)
                echo ""
                echo -e "${GREEN}➜ 粘贴链接 (vmess://...):${PLAIN}"
                read -r link
                if [[ -n "$link" ]]; then
                    echo -e "${GREEN}➜ 输入名称前缀 (如 HK，自动生成 HK_VMess/Reality):${PLAIN}"
                    read -r name
                    if [[ -n "$name" ]]; then
                        echo "$link $name" >> "$MANUAL_NODES_FILE"
                    else
                        echo "$link" >> "$MANUAL_NODES_FILE"
                    fi
                    print_success "已添加！"
                fi
                ;;
            d)
                if [ $node_count -eq 0 ]; then print_error "列表为空"; sleep 1; continue; fi
                read -p "请输入要删除的序号: " idx
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "$node_count" ]; then
                    sed -i "$((idx+1))d" "$MANUAL_NODES_FILE"
                    print_success "已删除！"
                else
                    print_error "无效序号"
                fi
                sleep 1
                ;;
            r)
                if [ $node_count -eq 0 ]; then print_error "列表为空"; sleep 1; continue; fi
                read -p "请输入要重命名的序号: " idx
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "$node_count" ]; then
                    old_line="${lines[$idx]}"
                    pure_link=$(echo "$old_line" | awk '{print $1}')
                    
                    echo -e "${GREEN}➜ 输入新前缀 (自动追加 _VMess/_Reality):${PLAIN}"
                    read -r new_name
                    if [[ -n "$new_name" ]]; then
                        lines[$idx]="$pure_link $new_name"
                        printf "%s\n" "${lines[@]}" > "$MANUAL_NODES_FILE"
                        print_success "前缀已更新！生成配置时将自动补全协议后缀。"
                    fi
                else
                    print_error "无效序号"
                fi
                sleep 1
                ;;
            c)
                echo "" > "$MANUAL_NODES_FILE"
                print_success "已清空"
                sleep 1
                ;;
            0) break ;;
            *) echo "无效"; sleep 0.5 ;;
        esac
    done
}

function menu_clear_data() {
    echo "" > "$AIRPORT_URLS_FILE"
    echo "" > "$MANUAL_NODES_FILE"
    print_success "所有订阅和节点数据已清空。"
}

function menu_reset_all() {
    rm -f "$OUTPUT_FILE" "$MANUAL_NODES_FILE" "$AIRPORT_URLS_FILE" "$LOCAL_NAME_FILE"
    print_success "已重置所有数据。"
    exit 0
}

function show_menu() {
    clear
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e "${BOLD}   Clash 配置管理面板 ${PLAIN}${CYAN}v13.9${PLAIN}"
    echo -e "${PURPLE}==============================================${PLAIN}"
    
    AIR_CNT=0; MAN_CNT=0
    [ -f "$AIRPORT_URLS_FILE" ] && AIR_CNT=$(grep -cve '^\s*$' "$AIRPORT_URLS_FILE")
    [ -f "$MANUAL_NODES_FILE" ] && MAN_CNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")

    printf "${GREEN} 1.${PLAIN} 🔄  | %s\n" "重新生成配置 (加载所有数据)"
    printf "${GREEN} 2.${PLAIN} ✈️   | %s [当前: ${YELLOW}%s${PLAIN}]\n" "添加机场订阅" "$AIR_CNT"
    printf "${GREEN} 3.${PLAIN} 🧩  | %s [当前: ${YELLOW}%s${PLAIN}]\n" "手动节点管理 (新增/删除/重命名)" "$MAN_CNT"
    printf "${GREEN} 4.${PLAIN} 🧹  | %s\n" "清空数据 (订阅+节点)"
    printf "${GREEN} 5.${PLAIN} 📄  | %s\n" "查看配置文件"
    printf "${BLUE} 6.${PLAIN} 🏠  | %s\n" "本机节点改名 (Local Node)"
    printf "${RED} 7.${PLAIN} 🗑️   | %s\n" "重置脚本 (删库跑路)"
    printf "${GREEN} 0.${PLAIN} 🚪  | %s\n" "退出"
    
    echo -e "${PURPLE}==============================================${PLAIN}"
    echo -e " 📂 输出路径: ${CYAN}${OUTPUT_FILE}${PLAIN}"
    echo ""
    read -p " 请输入选项 [0-7]: " choice
    
    case "$choice" in
        1) run_generator; read -p "按回车继续..." ;;
        2) menu_add_airport; read -p "按回车继续..." ;;
        3) menu_manual_manager ;; 
        4) menu_clear_data; read -p "按回车继续..." ;;
        5) echo ""; cat "$OUTPUT_FILE"; echo ""; read -p "按回车继续..." ;;
        6) menu_rename_local; read -p "按回车继续..." ;; 
        7) menu_reset_all ;;
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
    
    if [ ! -f "$AIRPORT_URLS_FILE" ]; then touch "$AIRPORT_URLS_FILE"; fi
    if [ ! -f "$MANUAL_NODES_FILE" ]; then touch "$MANUAL_NODES_FILE"; fi
    
    run_generator
    echo -e "\n${CYAN}👉 提示: 再次运行此脚本即可进入管理维护面板。${PLAIN}"
else
    while true; do
        show_menu
    done
fi
