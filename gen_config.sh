#!/bin/bash

# ==============================================================
# Clash 配置生成脚本 (v6.0 格式完美修复版)
# 修复: 缩进错误、空行缺失、名称汇总丢失
# ==============================================================

# 1. 基础配置
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
OUTPUT_FILE="/root/clash_final.yaml"
PORT_REALITY=443
PORT_TLS=8443

# --- 颜色定义 ---
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
CYAN='\033[36m'
PLAIN='\033[0m'

# ===========================================
# 0. 初始化
# ===========================================
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3${PLAIN}"
fi

# [修复3] 调整 Python 脚本输出缩进
# 确保每一行前面都有 2 个空格，符合 proxies: 列表格式
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse
def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        # 注意：这里每一行前面加了 2 个空格
        return f"""  - name: "{data.get('ps', 'Imported-VMess')}"\n    type: vmess\n    server: {data.get('add')}\n    port: {data.get('port')}\n    uuid: {data.get('id')}\n    alterId: {data.get('aid', 0)}\n    cipher: {data.get('scy', 'auto')}\n    udp: true\n    tls: {str(data.get('tls', '') == 'tls').lower()}\n    network: {data.get('net', 'tcp')}\n    servername: {data.get('host', '') or data.get('sni', '')}\n    ws-opts:\n      path: {data.get('path', '/')}\n      headers:\n        Host: {data.get('host', '') or data.get('sni', '')}\n"""
    except:
        return None
if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
EOF

# ===========================================
# 2. 下载模板
# ===========================================
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"
if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 模板下载失败${PLAIN}"
    exit 1
fi

# ===========================================
# 3. 多机场订阅 (保持不变)
# ===========================================
echo -e "${CYAN}📡 机场订阅配置${PLAIN}"
providers_yaml=""
group_use_yaml=""
count=0

while true; do
    if [ $count -eq 0 ]; then read -p "❓ 添加机场订阅？[y/n]: " add_sub
    else read -p "❓ 继续添加？[y/n]: " add_sub; fi
    [[ "$add_sub" != "y" && "$add_sub" != "Y" ]] && break

    echo -e "${YELLOW}粘贴订阅地址:${PLAIN}"
    read -r sub_url
    if [[ -n "$sub_url" ]]; then
        count=$((count+1))
        p_name="Airport_${count}"
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

# ===========================================
# 4. 生成本机节点 (修复缩进与空行)
# ===========================================
echo -e "${BLUE}🔍 生成本机节点...${PLAIN}"
AUTO_NODES_TEMP="auto_nodes.tmp"
echo "" > "$AUTO_NODES_TEMP"

if [ -f "$INFO_FILE" ]; then
    source "$INFO_FILE"
    IP=$(curl -s https://api.ipify.org)
    
    # [修复1] 每个节点末尾加一个空行
    # [修复2] client-fingerprint 缩进对齐 (6个空格，属于 reality-opts)
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
fi

# ===========================================
# 5. 手动节点管理 (修复整体缩进)
# ===========================================
echo "========================================"
# ... (清理逻辑保持不变) ...
if [ -f "$MANUAL_NODES_FILE" ]; then
    read -p "❓ 保留旧的手动节点？(y/n): " keep_manual
    if [[ "$keep_manual" == "n" || "$keep_manual" == "N" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
    fi
else
    touch "$MANUAL_NODES_FILE"
fi

read -p "❓ 添加新手动节点？[y/n]: " add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    echo -e "${YELLOW}粘贴链接:${PLAIN}"
    read -r manual_link
    [[ -n "$manual_link" ]] && echo "$manual_link" >> "$MANUAL_NODES_FILE"
fi

MANUAL_NODES_TEMP="manual_nodes.tmp"
echo "" > "$MANUAL_NODES_TEMP"
if [ -f "$MANUAL_NODES_FILE" ]; then
    while read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        if [[ "$line" == vmess://* ]]; then
            # Python 脚本里已经处理好了缩进
            python3 vmess_parser.py "$line" >> "$MANUAL_NODES_TEMP"
            echo "" >> "$MANUAL_NODES_TEMP" # 加个空行
        else
            # [修复3] 如果是原始 YAML 文本，手动加缩进 (2个空格)
            echo "  $line" >> "$MANUAL_NODES_TEMP"
        fi
    done < "$MANUAL_NODES_FILE"
fi

# ===========================================
# 6. 提取名称 (修复提取逻辑)
# ===========================================
NODE_NAMES=""

# [修复4] 提取名称时，允许前面有空格
# 使用 grep 提取包含 name: 的行，再用 awk
# 我们的节点格式通常是: "  - name: xxx"

for temp_file in "$AUTO_NODES_TEMP" "$MANUAL_NODES_TEMP"; do
    if [ -f "$temp_file" ]; then
        while read -r line; do
            # 忽略空行
            [[ -z "$line" ]] && continue
            
            # 匹配 name 字段 (允许前导空格)
            if [[ "$line" =~ name: ]]; then
                # 提取引号里的内容
                NAME=$(echo "$line" | awk -F'name: ' '{print $2}' | tr -d '"' | tr -d "'")
                # 去除可能的前后空格
                NAME=$(echo "$NAME" | xargs)
                
                if [[ -n "$NAME" ]]; then
                    # 拼接到列表里 (6个空格缩进，因为是在 proxies: 下面)
                    NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
                fi
            fi
        done < "$temp_file"
    fi
done

# ===========================================
# 7. 拼接与输出
# ===========================================
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

echo -e "${GREEN}🎉 生成成功: ${OUTPUT_FILE}${PLAIN}"
read -p "❓ 打印内容? [y/n]: " print_content
if [[ "$print_content" == "y" || "$print_content" == "Y" ]]; then
    cat "$OUTPUT_FILE"
fi
