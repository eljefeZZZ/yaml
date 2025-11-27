#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"

# 2. 安装脚本的信息文件路径
INFO_FILE="/usr/local/eljefe-v2/info.txt"

# 3. 手动维护的节点文件路径
MANUAL_NODES_FILE="/root/manual_nodes.yaml"

# 4. 输出文件
OUTPUT_FILE="/root/clash_final.yaml"

# 5. 端口定义
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

# --- 0. 初始化与清理 ---
echo -e "${BLUE}🧹 [系统] 正在清理旧文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

# --- 1. 环境检查与 Python 解析器准备 ---
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，链接转换功能不可用。${PLAIN}"
fi

cat << 'EOF' > vmess_parser.py
import sys
import base64
import json
import urllib.parse

def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        # 1. JSON format
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        return f"""- name: "{data.get('ps', 'Imported-VMess')}"
  type: vmess
  server: {data.get('add')}
  port: {data.get('port')}
  uuid: {data.get('id')}
  alterId: {data.get('aid', 0)}
  cipher: {data.get('scy', 'auto')}
  udp: true
  tls: {str(data.get('tls', '') == 'tls').lower()}
  network: {data.get('net', 'tcp')}
  servername: {data.get('host', '') or data.get('sni', '')}
  ws-opts:
    path: {data.get('path', '/')}
    headers:
      Host: {data.get('host', '') or data.get('sni', '')}
"""
    except:
        # 2. URL Params format
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
            
            return f"""- name: "{name}"
  type: vmess
  server: {server}
  port: {port}
  uuid: {uuid}
  alterId: {params.get('alterId', 0)}
  cipher: auto
  udp: true
  tls: {tls}
  network: {net}
  servername: {host}
  ws-opts:
    path: {params.get('path', '/')}
    headers:
      Host: {host}
"""
        except: return None

if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
        else: sys.exit(1)
EOF

echo -e "${BLUE}⬇️  [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

# 检查下载结果
if grep -q "404: Not Found" template.tmp || grep -q "404 Not Found" template.tmp; then
    echo -e "${RED}❌ 错误：模板 URL 无效 (404)。请检查脚本中的 TEMPLATE_URL。${PLAIN}"
    rm template.tmp vmess_parser.py
    exit 1
fi
if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 错误：下载的文件不是有效的 YAML 模板。${PLAIN}"
    rm template.tmp vmess_parser.py
    exit 1
fi

# --- 步骤 1.5: 询问并替换机场订阅 ---
echo "========================================"
read -p "❓ 是否添加机场订阅链接？[y/n]: " add_sub
if [[ "$add_sub" == "y" || "$add_sub" == "Y" ]]; then
    echo -e "${YELLOW}请粘贴订阅地址 (http/https开头):${PLAIN}"
    read -r sub_url
    if [[ -n "$sub_url" ]]; then
        # 使用 sed 整行替换 (c命令)，避免特殊字符干扰
        # 匹配包含 "这里填写机场订阅地址" 的行，替换为新的 url 行 (带4空格缩进)
        sed -i "/这里填写机场订阅地址/c\    url: \"$sub_url\"" template.tmp
        echo -e "${GREEN}✅ 订阅链接已更新。${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空，跳过。${PLAIN}"
    fi
else
    echo -e "${CYAN}ℹ️  跳过订阅设置，保留默认占位符。${PLAIN}"
fi

# --- 步骤 2: 动态生成自动节点 ---
echo -e "${BLUE}🔍 [处理] 读取本机自动节点信息...${PLAIN}"
AUTO_NODES_TEMP="auto_nodes_generated.tmp"
echo "" > "$AUTO_NODES_TEMP"

if [ ! -f "$INFO_FILE" ]; then
    echo -e "${YELLOW}⚠️  未找到本机 V2Ray 信息文件，跳过自动生成。${PLAIN}"
else
    source "$INFO_FILE"
    IP=$(curl -s https://api.ipify.org)
    
    # 修复重点：client-fingerprint 与 reality-opts 同级，不缩进
    cat <<EOF >> "$AUTO_NODES_TEMP"
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
        cat <<EOF >> "$AUTO_NODES_TEMP"
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
        cat <<EOF >> "$AUTO_NODES_TEMP"
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

# --- 步骤 3: 交互式添加手动节点 ---
echo "========================================"
if [ -s "$MANUAL_NODES_FILE" ]; then
    NODE_COUNT=$(grep -c "name:" "$MANUAL_NODES_FILE")
    echo -e "${CYAN}ℹ️  发现已有 $NODE_COUNT 个手动保存的节点。${PLAIN}"
    read -p "❓ 是否【清空】旧的手动节点？(y=清空 / n=保留) [y/n]: " clean_manual
    if [[ "$clean_manual" == "y" || "$clean_manual" == "Y" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
        echo -e "${GREEN}🗑️  旧节点已清空。${PLAIN}"
    else
        echo -e "${GREEN}👌 旧节点已保留。${PLAIN}"
    fi
fi

read -p "❓ 是否要【添加】新的 vmess:// 链接? [y/n]: " add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    while true; do
        echo -e "${YELLOW}请粘贴链接 (Ctrl+C 退出，直接回车结束):${PLAIN}"
        read -r vmess_link
        if [[ -z "$vmess_link" ]]; then break; fi
        
        echo "🔄 解析中..."
        PARSED_YAML=$(python3 vmess_parser.py "$vmess_link")
        
        if [[ $? -eq 0 && -n "$PARSED_YAML" ]]; then
            NODE_NAME=$(echo "$PARSED_YAML" | grep "name:" | head -1 | cut -d'"' -f2)
            echo -e "${GREEN}✅ 成功识别: $NODE_NAME${PLAIN}"
            [ ! -f "$MANUAL_NODES_FILE" ] && touch "$MANUAL_NODES_FILE"
            echo "$PARSED_YAML" >> "$MANUAL_NODES_FILE"
            echo "" >> "$MANUAL_NODES_FILE"
        else
            echo -e "${RED}❌ 解析失败，链接格式错误。${PLAIN}"
        fi
        echo "----------------------------------------"
    done
fi

# --- 步骤 4: 整合与生成 ---
extract_names() {
    local file=$1
    if [ -f "$file" ]; then
        grep -E "^[[:space:]]*-[[:space:]]*name:" "$file" | \
        sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//;s/^\x27//;s/\x27$//' | \
        while read -r name; do echo "
