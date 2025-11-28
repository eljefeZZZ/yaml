#!/bin/bash

# ==============================================================
# Clash 配置生成脚本 (多机场订阅 + 自动/手动节点混合版)
# 适配模板：clash_template_pro.yaml (含 #VAR_# 占位符)
# ==============================================================

# 1. 路径与变量定义
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
OUTPUT_FILE="/root/clash_final.yaml"

# 端口定义 (需与服务端保持一致)
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
# 0. 初始化与清理
# ===========================================
echo -e "${BLUE}🧹 [系统] 正在清理旧临时文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

# ===========================================
# 1. 准备 Python 链接解析工具 (用于手动 VMess 链接)
# ===========================================
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，VMess 链接转换功能将不可用。${PLAIN}"
fi

# 生成 Python 解析脚本 (完整版，防止解析失败)
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse

def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        # 尝试标准 Base64 解码
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        # 标准 V2rayN 格式
        return f"""- name: "{data.get('ps', 'Imported-VMess')}"\n  type: vmess\n  server: {data.get('add')}\n  port: {data.get('port')}\n  uuid: {data.get('id')}\n  alterId: {data.get('aid', 0)}\n  cipher: {data.get('scy', 'auto')}\n  udp: true\n  tls: {str(data.get('tls', '') == 'tls').lower()}\n  network: {data.get('net', 'tcp')}\n  servername: {data.get('host', '') or data.get('sni', '')}\n  ws-opts:\n    path: {data.get('path', '/')}\n    headers:\n      Host: {data.get('host', '') or data.get('sni', '')}\n"""
    except:
        try:
            # 尝试 QuanX/Shadowrocket 风格参数解析
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
# 2. 下载配置模板
# ===========================================
echo -e "${BLUE}⬇️ [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

# 检查模板有效性
if grep -q "404: Not Found" template.tmp || grep -q "404 Not Found" template.tmp; then
    echo -e "${RED}❌ 错误：模板 URL 无效 (404)。${PLAIN}"
    rm template.tmp vmess_parser.py
    exit 1
fi

if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 错误：下载的文件不是有效的 YAML 模板。${PLAIN}"
    rm template.tmp vmess_parser.py
    exit 1
fi

# ===========================================
# 3. 多机场订阅处理 (循环询问)
# ===========================================
echo "========================================"
echo -e "${CYAN}📡 机场订阅配置 (支持添加多个)${PLAIN}"

providers_yaml=""
group_use_yaml=""
airport_count=0

while true; do
    if [ $airport_count -eq 0 ]; then
        read -p "❓ 是否添加第一个机场订阅？[y/n]: " add_sub
    else
        read -p "❓ 是否继续添加第 $((airport_count+1)) 个机场？[y/n]: " add_sub
    fi

    if [[ "$add_sub" != "y" && "$add_sub" != "Y" ]]; then
        break
    fi

    echo -e "${YELLOW}请粘贴第 $((airport_count+1)) 个机场的订阅地址:${PLAIN}"
    read -r sub_url

    if [[ -n "$sub_url" ]]; then
        airport_count=$((airport_count+1))
        provider_name="Airport_${airport_count}"
        
        # 生成 Provider 配置块 (注意缩进)
        # 使用 \n 手动构建多行字符串
        providers_yaml="${providers_yaml}  ${provider_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${airport_count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
        
        # 生成策略组 use 列表
        group_use_yaml="${group_use_yaml}      - ${provider_name}\n"
        
        echo -e "${GREEN}✅ 已添加: ${provider_name}${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空，跳过。${PLAIN}"
    fi
done

# 注入机场配置到模板
if [ $airport_count -gt 0 ]; then
    echo -e "${BLUE}⚙️ 正在注入 ${airport_count} 个机场配置...${PLAIN}"
    
    # 1. 替换 proxy-providers 下的默认 Airport 块
    # 假设模板里有 "  Airport:" 这一行，删除它及后面几行
    sed -i '/^  Airport:/,+8d' template.tmp
    # 在 proxy-providers: 后插入新的
    sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
    
    # 2. 替换 proxy-groups 下的 use 列表
    # 删除旧的 "- Airport"
    sed -i '/- Airport/d' template.tmp
    # 在 "    use:" 后插入新的列表
    sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
    
    echo -e "${GREEN}✅ 多机场配置注入完成。${PLAIN}"
else
    echo -e "${CYAN}ℹ️ 未添加任何机场，保留默认配置 (需手动修改)。${PLAIN}"
fi

# ===========================================
# 4. 自动生成本机 Reality/VLESS 节点
# ===========================================
echo -e "${BLUE}🔍 [处理] 读取本机自动节点信息...${PLAIN}"
AUTO_NODES_TEMP="auto_nodes.tmp"
echo "" > "$AUTO_NODES_TEMP"

if [ ! -f "$INFO_FILE" ]; then
    echo -e "${YELLOW}⚠️ 未找到本机 V2Ray 信息文件，跳过自动生成。${PLAIN}"
else
    source "$INFO_FILE"
    IP=$(curl -s https://api.ipify.org)
    
    # 生成 Reality 节点
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

    # 生成 CDN 节点 (如果有域名)
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
# 5. 处理手动添加的节点 (Manual Nodes)
# ===========================================
echo -e "${BLUE}🔍 [处理] 检查手动节点文件...${PLAIN}"
MANUAL_NODES_TEMP="manual_nodes.tmp"
echo "" > "$MANUAL_NODES_TEMP"

if [ -f "$MANUAL_NODES_FILE" ]; then
    while read -r line; do
        # 忽略注释和空行
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        if [[ "$line" == vmess://* ]]; then
            # 解析 VMess 链接
            python3 vmess_parser.py "$line" >> "$MANUAL_NODES_TEMP"
        else
            # 假设是 YAML 格式，直接追加
            echo "$line" >> "$MANUAL_NODES_TEMP"
        fi
    done < "$MANUAL_NODES_FILE"
fi

# ===========================================
# 6. 提取所有节点名称 (用于填充自建策略组)
# ===========================================
echo -e "${BLUE}🔨 [构建] 正在提取节点名称...${PLAIN}"
NODE_NAMES=""

# 6.1 提取自动节点的名称
if [ -f "$AUTO_NODES_TEMP" ]; then
    while read -r line; do
        if [[ "$line" == *"- name:"* ]]; then
            NAME=$(echo "$line" | awk -F'"' '{print $2}')
            if [[ -n "$NAME" ]]; then
                NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
            fi
        fi
    done < "$AUTO_NODES_TEMP"
fi

# 6.2 提取手动节点的名称
if [ -f "$MANUAL_NODES_TEMP" ]; then
    while read -r line; do
        if [[ "$line" == *"- name:"* ]]; then
            NAME=$(echo "$line" | awk -F'"' '{print $2}')
            if [[ -n "$NAME" ]]; then
                NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
            fi
        fi
    done < "$MANUAL_NODES_TEMP"
fi

# ===========================================
# 7. 拼接最终 YAML (替换所有占位符)
# ===========================================
echo -e "${BLUE}🔨 [构建] 正在生成最终 YAML...${PLAIN}"

# 7.1 替换 #VAR_AUTO_NODES# (使用 sed r 命令)
if [ -s "$AUTO_NODES_TEMP" ]; then
    sed -i '/#VAR_AUTO_NODES#/r auto_nodes.tmp' template.tmp
fi
sed -i '/#VAR_AUTO_NODES#/d' template.tmp

# 7.2 替换 #VAR_MANUAL_NODES#
if [ -s "$MANUAL_NODES_TEMP" ]; then
    sed -i '/#VAR_MANUAL_NODES#/r manual_nodes.tmp' template.tmp
fi
sed -i '/#VAR_MANUAL_NODES#/d' template.tmp

# 7.3 替换 #VAR_ALL_NODE_NAMES# (使用临时文件辅助)
if [[ -n "$NODE_NAMES" ]]; then
    echo -e "$NODE_NAMES" > node_names.tmp
    sed -i '/#VAR_ALL_NODE_NAMES#/r node_names.tmp' template.tmp
    rm -f node_names.tmp
fi
sed -i '/#VAR_ALL_NODE_NAMES#/d' template.tmp

# 移动并设置权限
mv template.tmp "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"

# 清理
rm -f auto_nodes.tmp manual_nodes.tmp vmess_parser.py

# ===========================================
# 8. 完成
# ===========================================
echo -e "${GREEN}🎉 配置生成成功！文件位置: ${OUTPUT_FILE}${PLAIN}"
echo -e "${CYAN}👉 请下载该文件并导入 Clash 客户端。${PLAIN}"
