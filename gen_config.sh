#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/6fb07448c86ea075b11476ea4b5685612b320d33/clash_template.yaml"

# 2. 安装脚本的信息文件路径 (根据 setup.sh 分析得出)
INFO_FILE="/usr/local/eljefe-v2/info.txt"

# 3. 手动维护的节点文件路径
MANUAL_NODES_FILE="/root/manual_nodes.yaml"

# 4. 输出文件
OUTPUT_FILE="/root/clash_final.yaml"

# 5. 端口定义 (必须与 setup.sh 保持一致)
PORT_REALITY=443
PORT_TLS=8443
# ===========================================

echo "⬇️  正在下载配置模板..."
curl -s -o template.tmp "$TEMPLATE_URL"
if [ $? -ne 0 ]; then echo "❌ 下载失败"; exit 1; fi

# --- 步骤 1: 动态生成自动节点信息 ---
echo "🔍 读取节点原始信息..."
if [ ! -f "$INFO_FILE" ]; then
    echo "❌ 错误：未找到信息文件 $INFO_FILE，请确认 V2Ray 是否已安装。"
    rm template.tmp
    exit 1
fi

# 加载变量: UUID, PUB_KEY, SID, DOMAIN, SNI
source "$INFO_FILE"
# 获取本机 IP
IP=$(curl -s https://api.ipify.org)

# 临时存放生成的 YAML 节点
AUTO_NODES_TEMP="auto_nodes_generated.tmp"
echo "" > "$AUTO_NODES_TEMP"

echo "🛠️  正在构建 Reality 节点..."
# 1. 生成 Reality 节点
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

# 2. 如果有域名，生成 VLESS 和 VMess 节点
if [[ -n "$DOMAIN" ]]; then
    echo "🛠️  正在构建 VLESS/VMess CDN 节点..."
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

# --- 函数：提取节点名称 ---
extract_names() {
    local file=$1
    if [ -f "$file" ]; then
        grep "name:" "$file" | sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//;s/^\x27//;s/\x27$//' | while read -r name; do
            echo "      - \"$name\""
        done
    fi
}

# --- 处理节点内容缩进 ---
echo "📄 格式化节点内容..."

# 自动节点
if [ -s "$AUTO_NODES_TEMP" ]; then
    sed 's/^/  /' "$AUTO_NODES_TEMP" > auto_content.tmp
    extract_names "$AUTO_NODES_TEMP" > auto_names.tmp
else
    echo "" > auto_content.tmp
    echo "" > auto_names.tmp
fi

# 手动节点
if [ -f "$MANUAL_NODES_FILE" ]; then
    sed 's/^/  /' "$MANUAL_NODES_FILE" > manual_content.tmp
    extract_names "$MANUAL_NODES_FILE" > manual_names.tmp
else
    echo "" > manual_content.tmp
    echo "" > manual_names.tmp
fi

# 合并名字
cat auto_names.tmp manual_names.tmp > all_names.tmp

if [ ! -s all_names.tmp ]; then
    echo "❌ 错误：未生成任何节点信息。"
    rm *.tmp
    exit 1
fi

# --- 最终替换 ---
echo "⚙️  正在合并生成最终配置..."

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
rm *.tmp

echo "========================================"
echo "✅ 成功！配置文件已生成: $OUTPUT_FILE"
echo "包含节点数: $(grep "name:" "$OUTPUT_FILE" | grep -v "策略组" | wc -l)"
echo "========================================"
