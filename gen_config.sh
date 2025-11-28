#!/bin/bash

# ==============================================================
# Clash 配置生成脚本 (多机场 + 交互式手动节点管理)
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
# 0. 初始化与系统清理
# ===========================================
echo -e "${BLUE}🧹 [系统] 正在清理临时文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

# ===========================================
# 1. 准备 Python 工具
# ===========================================
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，链接转换功能不可用。${PLAIN}"
fi

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
            pad = len(b64)%4; 
            if pad: b64 += '='*(4-pad)
            decoded = base64.b64decode(b64).decode('utf-8')
            user, host_info = decoded.split('@')
            uuid = user.split(':')[1]
            server, port = host_info.split(':')
            params = dict(urllib.parse.parse_qsl(query))
            name = params.get('remarks', 'Imported-VMess')
            net = params.get('obfs', 'tcp'); 
            if net == 'websocket': net = 'ws'
            tls = 'true' if params.get('tls')=='1' else 'false'
            host = params.get('obfsParam') or params.get('peer') or server
            return f"""- name: "{name}"\n  type: vmess\n  server: {server}\n  port: {port}\n  uuid: {uuid}\n  alterId: {params.get('alterId', 0)}\n  cipher: auto\n  udp: true\n  tls: {tls}\n  network: {net}\n  servername: {host}\n  ws-opts:\n    path: {params.get('path', '/')}\n    headers:\n      Host: {host}\n"""
        except: return None
if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
    else: sys.exit(1)
EOF

# ===========================================
# 2. 下载模板
# ===========================================
echo -e "${BLUE}⬇️ [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"
if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 错误：模板下载失败或格式错误。${PLAIN}"
    rm template.tmp vmess_parser.py
    exit 1
fi

# ===========================================
# 3. [多机场] 循环添加订阅
# ===========================================
echo "========================================"
echo -e "${CYAN}📡 机场订阅配置${PLAIN}"

providers_yaml=""
group_use_yaml=""
count=0

while true; do
    if [ $count -eq 0 ]; then
        read -p "❓ 是否添加机场订阅？[y/n]: " add_sub
    else
        read -p "❓ 是否继续添加第 $((count+1)) 个机场？[y/n]: " add_sub
    fi

    [[ "$add_sub" != "y" && "$add_sub" != "Y" ]] && break

    echo -e "${YELLOW}请粘贴订阅地址:${PLAIN}"
    read -r sub_url
    if [[ -n "$sub_url" ]]; then
        count=$((count+1))
        p_name="Airport_${count}"
        providers_yaml="${providers_yaml}  ${p_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
        group_use_yaml="${group_use_yaml}      - ${p_name}\n"
        echo -e "${GREEN}✅ 已添加: ${p_name}${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空。${PLAIN}"
    fi
done

# 注入多机场配置
if [ $count -gt 0 ]; then
    sed -i '/^  Airport:/,+8d' template.tmp
    sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
    sed -i '/- Airport/d' template.tmp
    sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
fi

# ===========================================
# 4. [本机节点] 自动生成
# ===========================================
echo -e "${BLUE}🔍 [处理] 生成本机 Reality/VLESS 节点...${PLAIN}"
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
EOF
        cat << EOF >> "$AUTO_NODES_TEMP"
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
# 5. [手动节点] 交互式管理与清理 (关键修正)
# ===========================================
echo "========================================"
echo -e "${CYAN}🛠️  手动节点管理${PLAIN}"

# 5.1 询问是否清理旧数据
if [ -f "$MANUAL_NODES_FILE" ]; then
    read -p "❓ 发现之前的节点文件，是否保留？(选 n 则清空) [y/n]: " keep_manual
    if [[ "$keep_manual" == "n" || "$keep_manual" == "N" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
        echo -e "${BLUE}🗑️  已清空旧的手动节点。${PLAIN}"
    else
        echo -e "${GREEN}✅ 保留旧节点，将在末尾追加。${PLAIN}"
    fi
else
    touch "$MANUAL_NODES_FILE"
fi

# 5.2 询问是否添加新节点
read -p "❓ 是否手动粘贴一个新的节点链接？[y/n]: " add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    echo -e "${YELLOW}请粘贴链接 (vmess://... 或 vless://...):${PLAIN}"
    read -r manual_link
    if [[ -n "$manual_link" ]]; then
        echo "$manual_link" >> "$MANUAL_NODES_FILE"
        echo -e "${GREEN}✅ 节点已保存。${PLAIN}"
    fi
fi

# 5.3 处理并注入手动节点
MANUAL_NODES_TEMP="manual_nodes.tmp"
echo "" > "$MANUAL_NODES_TEMP"
if [ -f "$MANUAL_NODES_FILE" ]; then
    while read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" == vmess://* ]]; then
            python3 vmess_parser.py "$line" >> "$MANUAL_NODES_TEMP"
        else
            echo "$line" >> "$MANUAL_NODES_TEMP"
        fi
    done < "$MANUAL_NODES_FILE"
fi

# ===========================================
# 6. 提取节点名称 & 拼接 YAML
# ===========================================
echo -e "${BLUE}🔨 [构建] 提取名称并生成最终文件...${PLAIN}"
NODE_NAMES=""

for temp_file in "$AUTO_NODES_TEMP" "$MANUAL_NODES_TEMP"; do
    if [ -f "$temp_file" ]; then
        while read -r line; do
            if [[ "$line" == *"- name:"* ]]; then
                NAME=$(echo "$line" | awk -F'"' '{print $2}')
                [[ -n "$NAME" ]] && NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
            fi
        done < "$temp_file"
    fi
done

# 替换 Auto 节点
if [ -s "$AUTO_NODES_TEMP" ]; then
    sed -i '/#VAR_AUTO_NODES#/r auto_nodes.tmp' template.tmp
fi
sed -i '/#VAR_AUTO_NODES#/d' template.tmp

# 替换 Manual 节点
if [ -s "$MANUAL_NODES_TEMP" ]; then
    sed -i '/#VAR_MANUAL_NODES#/r manual_nodes.tmp' template.tmp
fi
sed -i '/#VAR_MANUAL_NODES#/d' template.tmp

# 替换 名称列表
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
# 7. 完成与输出 (含打印功能)
# ===========================================
echo -e "${GREEN}🎉 配置生成成功！文件位置: ${OUTPUT_FILE}${PLAIN}"

echo "========================================"
read -p "❓ 是否直接打印文件内容到屏幕? [y/n]: " print_content
if [[ "$print_content" == "y" || "$print_content" == "Y" ]]; then
    echo -e "${CYAN}⬇️ --- 文件内容 --- ⬇️${PLAIN}"
    cat "$OUTPUT_FILE"
    echo -e "${CYAN}⬆️ --- 结束 --- ⬆️${PLAIN}"
else
    echo -e "${CYAN}👉 请使用 SFTP 下载。${PLAIN}"
fi
