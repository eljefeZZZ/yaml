#!/bin/bash

# ==============================================================
# Clash 配置生成神器 (v10.0 终极美化版)
# ==============================================================

# 1. 基础配置
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

# --- 辅助函数：打印带边框的标题 ---
function print_title() {
    echo -e "${PURPLE}┌──────────────────────────────────────────────┐${PLAIN}"
    echo -e "${PURPLE}│${PLAIN} ${BOLD}$1${PLAIN}"
    echo -e "${PURPLE}└──────────────────────────────────────────────┘${PLAIN}"
}

# --- 辅助函数：打印步骤 ---
function print_step() {
    echo -e "${BLUE}➜  $1${PLAIN}"
}

# --- 辅助函数：打印成功 ---
function print_success() {
    echo -e "${GREEN}✔  $1${PLAIN}"
}

# --- 辅助函数：打印错误 ---
function print_error() {
    echo -e "${RED}✖  $1${PLAIN}"
}

# ===========================================
# 0. 初始化
# ===========================================
clear
print_title "🚀 Clash 配置生成向导 v10.0"
echo -e "${CYAN}此脚本将帮助您生成适配 Clash Meta 的完美配置文件。${PLAIN}\n"

print_step "正在初始化环境..."
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️  警告: 未检测到 Python3，手动节点解析功能受限。${PLAIN}"
else
    print_success "Python3 环境检测通过"
fi

# [Python脚本]
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse
def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        return f"""- name: "{data.get('ps', 'Imported-VMess')}"\n  type: vmess\n  server: {data.get('add')}\n  port: {data.get('port')}\n  uuid: {data.get('id')}\n  alterId: {data.get('aid', 0)}\n  cipher: {data.get('scy', 'auto')}\n  udp: true\n  tls: {str(data.get('tls', '') == 'tls').lower()}\n  network: {data.get('net', 'tcp')}\n  servername: {data.get('host', '') or data.get('sni', '')}\n  ws-opts:\n    path: {data.get('path', '/')}\n    headers:\n      Host: {data.get('host', '') or data.get('sni', '')}\n"""
    except: return None
if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
EOF

# ===========================================
# 2. 下载模板
# ===========================================
print_step "正在下载最新配置模板..."
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

if ! grep -q "proxies:" template.tmp; then
    print_error "模板下载失败或格式无效！"
    exit 1
else
    print_success "模板下载成功"
fi

# ===========================================
# 3. 多机场订阅
# ===========================================
echo ""
print_title "📡 机场订阅设置"
echo -e "${CYAN}提示: 您可以添加多个机场订阅链接，脚本将自动为您配置负载均衡和故障转移。${PLAIN}"

providers_yaml=""
group_use_yaml=""
count=0

while true; do
    if [ $count -eq 0 ]; then 
        read -p "$(echo -e "${YELLOW}❓ 是否添加第一个机场订阅？[y/n]: ${PLAIN}")" add_sub
    else 
        read -p "$(echo -e "${YELLOW}❓ 是否继续添加第 $((count+1)) 个机场？[y/n]: ${PLAIN}")" add_sub
    fi
    
    [[ "$add_sub" != "y" && "$add_sub" != "Y" ]] && break

    echo -e "${GREEN}➜ 请粘贴订阅地址:${PLAIN}"
    read -r sub_url
    if [[ -n "$sub_url" ]]; then
        count=$((count+1))
        p_name="Airport_${count}"
        # 使用 Emoji 和颜色区分
        echo -e "${GREEN}   ✔ 已记录: ${p_name}${PLAIN}"
        providers_yaml="${providers_yaml}  ${p_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
        group_use_yaml="${group_use_yaml}      - ${p_name}\n"
    else
        print_error "地址不能为空"
    fi
done

if [ $count -gt 0 ]; then
    sed -i '/^  Airport:/,+8d' template.tmp
    sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
    sed -i '/- Airport/d' template.tmp
    sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
    print_success "成功注入 ${count} 个机场订阅"
fi

# ===========================================
# 4. 生成本机节点
# ===========================================
echo ""
print_title "🏠 本机节点生成"
print_step "正在读取本机 Reality/VLESS 配置..."

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
    print_success "本机节点生成完毕"
else
    echo -e "${YELLOW}⚠️  未找到本机配置信息文件，跳过自动生成。${PLAIN}"
fi

# ===========================================
# 5. 手动节点管理
# ===========================================
echo ""
print_title "🛠️  手动节点管理"
echo -e "${CYAN}提示: 您可以手动添加其他 VMess/VLESS 链接。${PLAIN}"

if [ -f "$MANUAL_NODES_FILE" ]; then
    read -p "$(echo -e "${YELLOW}❓ 发现旧的手动节点文件，是否保留？(n=清空) [y/n]: ${PLAIN}")" keep_manual
    if [[ "$keep_manual" == "n" || "$keep_manual" == "N" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
        echo -e "${BLUE}   🗑️  已清空旧数据${PLAIN}"
    else
        echo -e "${GREEN}   ✔  已保留旧数据${PLAIN}"
    fi
else
    touch "$MANUAL_NODES_FILE"
fi

read -p "$(echo -e "${YELLOW}❓ 是否添加新的节点链接？[y/n]: ${PLAIN}")" add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    echo -e "${GREEN}➜ 请粘贴链接 (vmess://...):${PLAIN}"
    read -r manual_link
    if [[ -n "$manual_link" ]]; then
        echo "$manual_link" >> "$MANUAL_NODES_FILE"
        print_success "链接已保存"
    fi
fi

MANUAL_NODES_TEMP="manual_nodes.tmp"
echo "" > "$MANUAL_NODES_TEMP"

if [ -s "$MANUAL_NODES_FILE" ]; then
    print_step "正在解析手动节点..."
    while read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^#.*$ ]] && continue
        
        if [[ "$line" == vmess://* ]]; then
            RESULT=$(python3 vmess_parser.py "$line")
            if [[ -n "$RESULT" ]]; then
                echo "$RESULT" >> "$MANUAL_NODES_TEMP"
                echo "" >> "$MANUAL_NODES_TEMP"
            else
                print_error "解析失败: ${line:0:20}..."
            fi
        else
            echo "$line" >> "$MANUAL_NODES_TEMP"
        fi
    done < "$MANUAL_NODES_FILE"
    print_success "手动节点处理完成"
fi

# ===========================================
# 6. 提取名称 & 7. 拼接
# ===========================================
echo ""
print_step "正在整合所有节点..."

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

# 拼接
if [ -s "$AUTO_NODES_TEMP" ]; then
    sed -i '/#VAR_AUTO_NODES#/r auto_nodes.tmp' template.tmp
fi
sed -i '/#VAR_AUTO_NODES#/d' template.tmp

if [ -s "$MANUAL_NODES_TEMP" ]; then
    sed -i '/#VAR_MANUAL_NODES#/r manual_nodes.tmp' template.tmp
fi
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

# ===========================================
# 8. 最终输出美化
# ===========================================
echo ""
print_title "🎉 恭喜！配置生成成功"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e " 📂 ${BOLD}文件位置:${PLAIN} ${CYAN}${OUTPUT_FILE}${PLAIN}"
echo -e " 📝 ${BOLD}文件权限:${PLAIN} ${CYAN}644 (rw-r--r--)${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"

echo ""
read -p "$(echo -e "${YELLOW}❓ 是否直接打印文件内容到屏幕？[y/n]: ${PLAIN}")" print_content
if [[ "$print_content" == "y" || "$print_content" == "Y" ]]; then
    echo -e "\n${PURPLE}⬇️  ---------------- 文件开始 ---------------- ⬇️${PLAIN}"
    # 使用 cat 配合 grep 高亮显示一些关键信息 (可选)
    # 这里直接 cat，简单明了
    cat "$OUTPUT_FILE"
    echo -e "${PURPLE}⬆️  ---------------- 文件结束 ---------------- ⬆️${PLAIN}\n"
else
    echo -e "${CYAN}👉 您可以使用 SFTP 下载该文件，或使用 'cat ${OUTPUT_FILE}' 查看。${PLAIN}\n"
fi
