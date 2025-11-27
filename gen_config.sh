#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址 (请修改为你实际的 Gist 地址)
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/6fb07448c86ea075b11476ea4b5685612b320d33/clash_template.yaml"

# 2. 安装脚本的信息文件路径 (setup.sh 生成的)
INFO_FILE="/usr/local/eljefe-v2/info.txt"

# 3. 手动维护的节点文件路径
MANUAL_NODES_FILE="/root/manual_nodes.yaml"

# 4. 输出文件
OUTPUT_FILE="/root/clash_final.yaml"

# 5. 端口定义 (需与 setup.sh 保持一致)
PORT_REALITY=443
PORT_TLS=8443
# ===========================================

echo "⬇️  正在下载配置模板..."
# 添加时间戳参数 ?t=$(date +%s) 防止 GitHub CDN 缓存旧文件
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"
if [ $? -ne 0 ]; then echo "❌ 下载失败，请检查网络或 URL。"; exit 1; fi

# --- 步骤 1: 动态生成自动节点信息 ---
echo "🔍 读取节点原始信息..."
if [ ! -f "$INFO_FILE" ]; then
    echo "❌ 错误：未找到信息文件 $INFO_FILE，请确认 V2Ray 是否已安装。"
    rm template.tmp
    exit 1
fi

# 加载变量: UUID, PUB_KEY, SID, DOMAIN, SNI
source "$INFO_FILE"
# 获取本机公网 IP
IP=$(curl -s https://api.ipify.org)

# 临时存放生成的 YAML 节点内容
AUTO_NODES_TEMP="auto_nodes_generated.tmp"
echo "" > "$AUTO_NODES_TEMP"

echo "🛠️  正在构建 Reality 节点..."
# 1. 生成 Reality 节点 (末尾保留空行以分隔节点)
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

# 2. 如果配置了域名，则生成 VLESS 和 VMess 节点
if [[ -n "$DOMAIN" ]]; then
    echo "🛠️  正在构建 VLESS/VMess CDN 节点..."
    
    # VLESS 节点 (末尾保留空行)
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

    # VMess 节点 (末尾保留空行)
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

# --- 函数：精准提取节点名称 ---
# 仅提取以 "- name:" 开头的行，排除 servername 等干扰
extract_names() {
    local file=$1
    if [ -f "$file" ]; then
        # grep -E 精准匹配行首结构，sed 清洗多余字符
        grep -E "^[[:space:]]*-[[:space:]]*name:" "$file" | \
        sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//;s/^\x27//;s/\x27$//' | \
        while read -r name; do
            echo "      - \"$name\""
        done
    fi
}

# --- 处理节点内容格式与缩进 ---
echo "📄 格式化节点内容..."

# 处理自动节点
if [ -s "$AUTO_NODES_TEMP" ]; then
    # 统一给内容加 2 格缩进，适配 YAML 的 proxies 层级
    sed 's/^/  /' "$AUTO_NODES_TEMP" > auto_content.tmp
    extract_names "$AUTO_NODES_TEMP" > auto_names.tmp
else
    echo "" > auto_content.tmp
    echo "" > auto_names.tmp
fi

# 处理手动节点 (如果有)
if [ -f "$MANUAL_NODES_FILE" ]; then
    sed 's/^/  /' "$MANUAL_NODES_FILE" > manual_content.tmp
    extract_names "$MANUAL_NODES_FILE" > manual_names.tmp
else
    echo "" > manual_content.tmp
    echo "" > manual_names.tmp
fi

# 合并所有节点名称到临时文件
cat auto_names.tmp manual_names.tmp > all_names.tmp

if [ ! -s all_names.tmp ]; then
    echo "❌ 错误：未生成任何节点信息 (自动或手动均为空)。"
    rm *.tmp
    exit 1
fi

# --- 最终合并替换 ---
echo "⚙️  正在合并生成最终配置..."

awk '
    BEGIN {
        # 读取所有片段内容
        while ((getline line < "auto_content.tmp") > 0) auto_c = auto_c line "\n"
        while ((getline line < "manual_content.tmp") > 0) manual_c = manual_c line "\n"
        while ((getline line < "all_names.tmp") > 0) names_c = names_c line "\n"
    }
    
    # 替换模板中的占位符
    /#VAR_AUTO_NODES#/ { printf "%s", auto_c; next }
    /#VAR_MANUAL_NODES#/ { printf "%s", manual_c; next }
    /#VAR_ALL_NODE_NAMES#/ { printf "%s", names_c; next }
    
    # 其他行原样保留
    { print }
' template.tmp > "$OUTPUT_FILE"

# --- 清理临时文件 ---
rm *.tmp

echo "========================================"
echo "✅ 成功！配置文件已生成: $OUTPUT_FILE"
echo "📊 包含节点数: $(grep -E "^[[:space:]]*-[[:space:]]*name:" "$OUTPUT_FILE" | grep -v "策略组" | wc -l)"
echo "⬇️  下载命令参考: curl --upload-file $OUTPUT_FILE https://transfer.sh/clash_final.yaml"
echo "========================================"
