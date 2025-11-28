#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"

# 2. 路径定义
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

# --- 0. 初始化与清理 ---
echo -e "${BLUE}🧹 [系统] 正在清理旧文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

# --- 1. 环境检查与 Python 解析器准备 ---
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，链接转换功能不可用。${PLAIN}"
fi

# 生成 Python 脚本
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse
def parse_vmess(link):
    if not link.startswith("vmess://"): return None
    b64_body = link[8:]
    try:
        decoded = base64.b64decode(b64_body).decode('utf-8')
        data = json.loads(decoded)
        return f"""- name: "{data.get('ps', 'Imported-VMess')}"\ntype: vmess\nserver: {data.get('add')}\nport: {data.get('port')}\nuuid: {data.get('id')}\nalterId: {data.get('aid', 0)}\ncipher: {data.get('scy', 'auto')}\nudp: true\ntls: {str(data.get('tls', '') == 'tls').lower()}\nnetwork: {data.get('net', 'tcp')}\nservername: {data.get('host', '') or data.get('sni', '')}\nws-opts:\n  path: {data.get('path', '/')}\n  headers:\n    Host: {data.get('host', '') or data.get('sni', '')}\n"""
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
            return f"""- name: "{name}"\ntype: vmess\nserver: {server}\nport: {port}\nuuid: {uuid}\nalterId: {params.get('alterId', 0)}\ncipher: auto\nudp: true\ntls: {tls}\nnetwork: {net}\nservername: {host}\nws-opts:\n  path: {params.get('path', '/')}\n  headers:\n    Host: {host}\n"""
        except: return None

if __name__ == "__main__":
    if len(sys.argv) > 1:
        res = parse_vmess(sys.argv[1])
        if res: print(res)
    else: sys.exit(1)
EOF

echo -e "${BLUE}⬇️ [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

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

# =======================================================
# 🚀 核心增强：循环添加多机场订阅
# =======================================================
echo "========================================"
echo -e "${CYAN}📡 机场订阅配置 (支持添加多个)${PLAIN}"

providers_yaml=""
group_use_yaml=""
count=0

while true; do
    if [ $count -eq 0 ]; then
        read -p "❓ 是否添加第一个机场订阅？[y/n]: " add_sub
    else
        read -p "❓ 是否继续添加第 $((count+1)) 个机场？[y/n]: " add_sub
    fi

    if [[ "$add_sub" != "y" && "$add_sub" != "Y" ]]; then
        break
    fi

    echo -e "${YELLOW}请粘贴第 $((count+1)) 个机场的订阅地址:${PLAIN}"
    read -r sub_url

    if [[ -n "$sub_url" ]]; then
        count=$((count+1))
        provider_name="Airport_${count}"
        
        # 关键修正：在 EOF 结束符前加回车，确保 YAML 格式正确
        providers_yaml="${providers_yaml}  ${provider_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
        
        group_use_yaml="${group_use_yaml}      - ${provider_name}\n"
        echo -e "${GREEN}✅ 已添加: ${provider_name}${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空，跳过。${PLAIN}"
    fi
done

# --- 将生成的 Provider 插入到模板 ---
if [ $count -gt 0 ]; then
    echo -e "${BLUE}⚙️ 正在注入 ${count} 个机场配置...${PLAIN}"
    
    # 删除模板原有的 Airport 示例
    sed -i '/^  Airport:/,+8d' template.tmp
    
    # 插入新的 Providers
    sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
    
    # 删除旧 use 列表项
    sed -i '/- Airport/d' template.tmp
    
    # 插入新 use 列表项
    sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
    
    echo -e "${GREEN}✅ 多机场配置注入完成。${PLAIN}"
else
    echo -e "${CYAN}ℹ️ 未添加任何机场，保留默认配置。${PLAIN}"
fi

# =======================================================
# 下面是被截断的部分，必须加上！
# =======================================================

# --- 步骤 2: 动态生成自动节点 ---
echo -e "${BLUE}🔍 [处理] 读取本机自动节点信息...${PLAIN}"
AUTO_NODES_TEMP="auto_nodes_generated.tmp"
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

    # 生成 VLESS/VMess CDN 节点 (如果有)
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

# --- 步骤 3: 处理手动节点 ---
echo -e "${BLUE}🔍 [处理] 检查手动节点文件...${PLAIN}"
if [ -f "$MANUAL_NODES_FILE" ]; then
    # 这里简化处理，假设手动节点文件里就是一行一个 vmess:// 链接
    while read -r line; do
        if [[ "$line" == vmess://* ]]; then
            python3 vmess_parser.py "$line" >> "$AUTO_NODES_TEMP"
        else
            # 如果是 YAML 格式的节点，直接追加
            echo "$line" >> "$AUTO_NODES_TEMP"
        fi
    done < "$MANUAL_NODES_FILE"
fi

# --- 步骤 4: 拼接最终 YAML ---
echo -e "${BLUE}🔨 [构建] 正在生成最终 YAML...${PLAIN}"

# 读取生成的节点名字
NODE_NAMES=""
while read -r line; do
    if [[ "$line" == *"- name:"* ]]; then
        NAME=$(echo "$line" | awk -F'"' '{print $2}')
        if [[ -n "$NAME" ]]; then
            NODE_NAMES="${NODE_NAMES}      - \"${NAME}\"\n"
        fi
    fi
done < "$AUTO_NODES_TEMP"

# 替换节点插入点
sed -i '/<AUTO_GENERATED_PROXIES_HERE>/r auto_nodes_generated.tmp' template.tmp
sed -i '/<AUTO_GENERATED_PROXIES_HERE>/d' template.tmp

# 替换自建节点组名称
# 注意：使用 awk 进行多行插入比较稳，或者直接用 sed 替换特定标记
if [[ -n "$NODE_NAMES" ]]; then
    # 删除原来的占位符
    sed -i '/<AUTO_GENERATED_PROXIES_NAMES>/d' template.tmp
    # 在 "🏠 我的自建组" 下面插入名字
    # 找到 "    proxies:" 且上一行包含 "🏠 我的自建组" 的地方插入（比较复杂）
    # 简单做法：我们在模板里留了一个 <AUTO_GENERATED_PROXIES_NAMES> 占位符
    # 由于 sed 对换行符处理比较麻烦，我们用 perl 或者 awk，或者分步替换
    
    # 简单替换法：
    perl -i -pe "s|<AUTO_GENERATED_PROXIES_NAMES>|$NODE_NAMES|g" template.tmp
else
    # 如果没有节点，删掉占位符
    sed -i '/<AUTO_GENERATED_PROXIES_NAMES>/d' template.tmp
fi

# 移动并重命名
mv template.tmp "$OUTPUT_FILE"
rm -f auto_nodes_generated.tmp vmess_parser.py

echo -e "${GREEN}🎉 配置生成成功！文件位置: ${OUTPUT_FILE}${PLAIN}"
echo -e "${CYAN}👉 请在客户端导入此文件即可使用。${PLAIN}"
