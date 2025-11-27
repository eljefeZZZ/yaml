#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/6fb07448c86ea075b11476ea4b5685612b320d33/clash_template.yaml"

# 2. 安装脚本的信息文件路径
INFO_FILE="/usr/local/eljefe-v2/info.txt"

# 3. 手动维护的节点文件路径
MANUAL_NODES_FILE="/root/manual_nodes.yaml"

# 4. 输出文件
OUTPUT_FILE="/root/clash_final.yaml"

# 5. 端口定义
PORT_REALITY=443
PORT_TLS=8443
# ===========================================

# --- 0. 环境检查与 Python 解析器准备 ---
# 检查 python3 是否存在 (解析链接需要)
if ! command -v python3 &> /dev/null; then
    echo "⚠️ 未检测到 Python3，将无法使用链接转换功能 (但自动生成仍可用)。"
fi

# 定义 Python 解析脚本 (通过 Heredoc 写入临时文件)
cat << 'EOF' > vmess_parser.py
import sys
import base64
import json
import urllib.parse

def parse_vmess(link):
    if not link.startswith("vmess://"):
        return None
    
    b64_body = link[8:]
    try:
        # 1. 尝试标准 JSON 格式
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        # 转换为 Clash YAML
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
        # 2. 尝试 URL 参数格式 (用户提供的格式)
        # 格式: vmess://BASE64?params
        try:
            if "?" in b64_body:
                b64_part, query_part = b64_body.split("?", 1)
            else:
                b64_part, query_part = b64_body, ""
            
            # 补全 padding
            missing_padding = len(b64_part) % 4
            if missing_padding:
                b64_part += '=' * (4 - missing_padding)
                
            decoded_base = base64.b64decode(b64_part).decode('utf-8')
            # 解码后格式通常为: type:uuid@host:port
            # 例如: auto:uuid@www.example.com:443
            
            user_info, host_info = decoded_base.split('@')
            uuid = user_info.split(':')[1]
            server, port = host_info.split(':')
            
            # 解析参数
            params = dict(urllib.parse.parse_qsl(query_part))
            
            name = params.get('remarks', 'Imported-VMess')
            network = params.get('obfs', 'tcp')
            if network == 'websocket': network = 'ws'
            
            tls = 'true' if params.get('tls') == '1' else 'false'
            path = params.get('path', '/')
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
  network: {network}
  servername: {host}
  ws-opts:
    path: {path}
    headers:
      Host: {host}
"""
        except Exception as e:
            print(f"Error parsing: {e}")
            return None

if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res:
            print(res)
        else:
            sys.exit(1)
EOF

echo "⬇️  正在下载配置模板..."
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"
if [ $? -ne 0 ]; then echo "❌ 下载失败"; exit 1; fi

# --- 步骤 1: 动态生成自动节点 ---
echo "🔍 读取本机自动节点信息..."
if [ ! -f "$INFO_FILE" ]; then
    echo "⚠️ 未找到本机 V2Ray 信息，跳过自动生成。"
else
    source "$INFO_FILE"
    IP=$(curl -s https://api.ipify.org)
    AUTO_NODES_TEMP="auto_nodes_generated.tmp"
    echo "" > "$AUTO_NODES_TEMP"

    # Reality
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

    # VLESS/VMess CDN
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

# --- 步骤 2: 交互式添加手动节点 ---
echo "========================================"
read -p "❓ 是否要添加手动节点链接(vmess://)? [y/n]: " add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    while true; do
        echo "请粘贴 vmess:// 链接 (按 Ctrl+C 退出，直接回车结束添加):"
        read -r vmess_link
        
        if [[ -z "$vmess_link" ]]; then break; fi
        
        echo "🔄 正在解析..."
        # 调用 Python 解析
        PARSED_YAML=$(python3 vmess_parser.py "$vmess_link")
        
        if [[ $? -eq 0 && -n "$PARSED_YAML" ]]; then
            # 提取节点名称用于显示
            NODE_NAME=$(echo "$PARSED_YAML" | grep "name:" | head -1 | cut -d'"' -f2)
            echo "✅ 成功识别节点: $NODE_NAME"
            
            # 确保手动文件存在
            if [ ! -f "$MANUAL_NODES_FILE" ]; then touch "$MANUAL_NODES_FILE"; fi
            
            # 追加到手动文件 (并追加一个空行)
            echo "$PARSED_YAML" >> "$MANUAL_NODES_FILE"
            echo "" >> "$MANUAL_NODES_FILE"
            echo "📥 已添加到手动节点列表。"
        else
            echo "❌ 解析失败，请检查链接格式。"
        fi
        echo "----------------------------------------"
        echo "还有吗？(直接回车结束)"
    done
fi

# --- 步骤 3: 提取名称与合并 ---
# 函数：精准提取节点名称
extract_names() {
    local file=$1
    if [ -f "$file" ]; then
        grep -E "^[[:space:]]*-[[:space:]]*name:" "$file" | \
        sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//;s/^\x27//;s/\x27$//' | \
        while read -r name; do
            echo "      - \"$name\""
        done
    fi
}

echo "📄 正在整合所有节点..."

# 自动节点处理
if [ -f "$AUTO_NODES_TEMP" ] && [ -s "$AUTO_NODES_TEMP" ]; then
    sed 's/^/  /' "$AUTO_NODES_TEMP" > auto_content.tmp
    extract_names "$AUTO_NODES_TEMP" > auto_names.tmp
else
    echo "" > auto_content.tmp
    echo "" > auto_names.tmp
fi

# 手动节点处理
if [ -f "$MANUAL_NODES_FILE" ] && [ -s "$MANUAL_NODES_FILE" ]; then
    sed 's/^/  /' "$MANUAL_NODES_FILE" > manual_content.tmp
    extract_names "$MANUAL_NODES_FILE" > manual_names.tmp
else
    echo "" > manual_content.tmp
    echo "" > manual_names.tmp
fi

# 合并名称
cat auto_names.tmp manual_names.tmp > all_names.tmp

if [ ! -s all_names.tmp ]; then
    echo "❌ 错误：没有有效的节点信息。"
    rm *.tmp vmess_parser.py
    exit 1
fi

# --- 步骤 4: 最终生成 ---
echo "⚙️  正在生成最终配置文件..."

awk '
    BEGIN {
        while ((getline line < "auto_content.tmp") > 0) auto_c = auto_c line "\n"
        while ((getline line < "manual_content.tmp") > 0) manual_c = manual_c line "\n"
        while ((getline line < "all_names.tmp") > 0) names_c = names_c line "\n"
    }
    /#VAR_AUTO_NODES#/ { printf "%s", auto_c; next }
    /#VAR_MANUAL_NODES#/ { printf "%s", manual_c; next }
    /#VAR_ALL_NODE_NAMES#/ { printf "%s", names_c; next }
    { print }
' template.tmp > "$OUTPUT_FILE"

# 清理
rm *.tmp vmess_parser.py

echo "========================================"
echo "✅ 配置文件已生成: $OUTPUT_FILE"
echo "📊 当前包含节点:"
extract_names "$OUTPUT_FILE" | sed 's/      - /  ⭐ /'
echo "========================================"
echo "⬇️  下载命令: curl --upload-file $OUTPUT_FILE https://transfer.sh/clash_final.yaml"
