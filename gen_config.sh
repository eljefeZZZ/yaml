#!/bin/bash

# ================= 配置区域 =================
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
OUTPUT_FILE="/root/clash_final.yaml"
PORT_REALITY=443
PORT_TLS=8443

GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
CYAN='\033[36m'
PLAIN='\033[0m'
# ===========================================

# 0. 清理
echo -e "${BLUE}🧹 [系统] 正在清理旧文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE"

# 1. 准备 Python 解析器 (使用最简写法避免转义地狱)
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，链接转换功能不可用。${PLAIN}"
fi

# 注意：这里使用 'EOF' (带单引号) 严格禁止变量替换
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse

def parse(link):
    if not link.startswith("vmess://"): return None
    b64 = link[8:]
    try:
        # JSON
        d = json.loads(base64.b64decode(b64).decode('utf-8'))
        return f'- name: "{d.get("ps","VMess")}"\n  type: vmess\n  server: {d.get("add")}\n  port: {d.get("port")}\n  uuid: {d.get("id")}\n  alterId: {d.get("aid",0)}\n  cipher: {d.get("scy","auto")}\n  udp: true\n  tls: {str(d.get("tls")=="tls").lower()}\n  network: {d.get("net","tcp")}\n  servername: {d.get("host") or d.get("sni")}\n  ws-opts:\n    path: {d.get("path","/")}\n    headers:\n      Host: {d.get("host") or d.get("sni")}\n'
    except:
        # URL Params
        try:
            if "?" in b64: b, q = b64.split("?", 1)
            else: b, q = b64, ""
            b += "=" * ((4 - len(b) % 4) % 4)
            dec = base64.b64decode(b).decode('utf-8')
            u, h = dec.split('@')
            uid = u.split(':')[1]
            srv, prt = h.split(':')
            p = dict(urllib.parse.parse_qsl(q))
            
            nm = p.get('remarks', 'VMess')
            net = 'ws' if p.get('obfs') == 'websocket' else p.get('obfs', 'tcp')
            tls = 'true' if p.get('tls') == '1' else 'false'
            host = p.get('obfsParam') or p.get('peer') or srv
            
            return f'- name: "{nm}"\n  type: vmess\n  server: {srv}\n  port: {prt}\n  uuid: {uid}\n  alterId: {p.get("alterId",0)}\n  cipher: auto\n  udp: true\n  tls: {tls}\n  network: {net}\n  servername: {host}\n  ws-opts:\n    path: {p.get("path","/")}\n    headers:\n      Host: {host}\n'
        except: return None

if __name__ == "__main__":
    if len(sys.argv) > 1:
        r = parse(sys.argv[1])
        if r: print(r)
        else: sys.exit(1)
EOF

echo -e "${BLUE}⬇️  [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

if grep -q "404" template.tmp; then
    echo -e "${RED}❌ 错误：模板 URL 无效 (404)。${PLAIN}"; rm template.tmp vmess_parser.py; exit 1
fi
if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 错误：无效的 YAML 模板。${PLAIN}"; rm template.tmp vmess_parser.py; exit 1
fi

# 1.5 替换订阅
echo "========================================"
read -p "❓ 是否添加机场订阅链接？[y/n]: " add_sub
if [[ "$add_sub" == "y" || "$add_sub" == "Y" ]]; then
    echo -e "${YELLOW}请粘贴订阅地址:${PLAIN}"
    read -r sub_url
    if [[ -n "$sub_url" ]]; then
        sed -i "/这里填写机场订阅地址/c\    url: \"$sub_url\"" template.tmp
        echo -e "${GREEN}✅ 订阅链接已更新。${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空。${PLAIN}"
    fi
else
    echo -e "${CYAN}ℹ️  跳过订阅设置。${PLAIN}"
fi

# 2. 生成自动节点
echo -e "${BLUE}🔍 [处理] 读取自动节点信息...${PLAIN}"
AUTO_NODES_TEMP="auto_nodes_generated.tmp"
echo "" > "$AUTO_NODES_TEMP"

if [ -f "$INFO_FILE" ]; then
    source "$INFO_FILE"
    IP=$(curl -s https://api.ipify.org)

    # Reality Node
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
        # VLESS CDN
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
        # VMess CDN
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
else
    echo -e "${YELLOW}⚠️  未找到 V2Ray 信息文件。${PLAIN}"
fi

# 3. 手动节点
echo "========================================"
if [ -s "$MANUAL_NODES_FILE" ]; then
    echo -e "${CYAN}ℹ️  发现旧的手动节点。${PLAIN}"
    read -p "❓ 是否【清空】旧节点？(y/n): " clean_manual
    [[ "$clean_manual" == "y" || "$clean_manual" == "Y" ]] && echo "" > "$MANUAL_NODES_FILE" && echo -e "${GREEN}已清空。${PLAIN}"
fi

read -p "❓ 是否添加新的 vmess:// 链接? [y/n]: " add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    while true; do
        echo -e "${YELLOW}粘贴链接 (回车结束):${PLAIN}"
        read -r vmess_link
        [[ -z "$vmess_link" ]] && break
        
        PARSED=$(python3 vmess_parser.py "$vmess_link")
        if [[ $? -eq 0 && -n "$PARSED" ]]; then
            NAME=$(echo "$PARSED" | grep "name:" | head -1 | cut -d'"' -f2)
            echo -e "${GREEN}✅ 识别: $NAME${PLAIN}"
            [ ! -f "$MANUAL_NODES_FILE" ] && touch "$MANUAL_NODES_FILE"
            echo "$PARSED" >> "$MANUAL_NODES_FILE"
            echo "" >> "$MANUAL_NODES_FILE"
        else
            echo -e "${RED}❌ 解析失败。${PLAIN}"
        fi
    done
fi

# 4. 合并
extract_names() {
    if [ -f "$1" ]; then
        grep -E "^[[:space:]]*-[[:space:]]*name:" "$1" | \
        sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//;s/^\x27//;s/\x27$//' | \
        while read -r n; do echo "      - \"$n\""; done
    fi
}

echo -e "${BLUE}⚙️  [合并] 正在生成...${PLAIN}"

[ -s "$AUTO_NODES_TEMP" ] && sed 's/^/  /' "$AUTO_NODES_TEMP" > ac.tmp && extract_names "$AUTO_NODES_TEMP" > an.tmp || { touch ac.tmp an.tmp; }
[ -s "$MANUAL_NODES_FILE" ] && sed 's/^/  /' "$MANUAL_NODES_FILE" > mc.tmp && extract_names "$MANUAL_NODES_FILE" > mn.tmp || { touch mc.tmp mn.tmp; }

cat an.tmp mn.tmp > all_names.tmp
if [ ! -s all_names.tmp ]; then
    echo -e "${RED}❌ 无有效节点。${PLAIN}"; rm *.tmp vmess_parser.py; exit 1
fi

awk '
    BEGIN {
        while ((getline < "ac.tmp") > 0) ac = ac $0 "\n"
        while ((getline < "mc.tmp") > 0) mc = mc $0 "\n"
        while ((getline < "all_names.tmp") > 0) nc = nc $0 "\n"
    }
    /#VAR_AUTO_NODES#/ { printf "%s", ac; next }
    /#VAR_MANUAL_NODES#/ { printf "%s", mc; next }
    /#VAR_ALL_NODE_NAMES#/ { printf "%s", nc; next }
    { print }
' template.tmp > "$OUTPUT_FILE"

rm *.tmp vmess_parser.py

# 5. 完成
echo "========================================"
echo -e "${GREEN}✅ 生成成功: $OUTPUT_FILE ${PLAIN}"
echo -e "${CYAN}📊 节点列表:${PLAIN}"
grep -E "^[[:space:]]*-[[:space:]]*name:" "$OUTPUT_FILE" | sed 's/.*name:[[:space:]]*//;s/^"//;s/"$//' | while read -r n; do echo -e "  ⭐ ${YELLOW}$n${PLAIN}"; done
echo "========================================"
echo -e "${GREEN}⬇️  下载 (Transfer.sh):${PLAIN}"
echo -e "   ${CYAN}curl --upload-file $OUTPUT_FILE https://transfer.sh/clash_final.yaml${PLAIN}"
echo ""
echo -e "${GREEN}👀 查看内容:${PLAIN}"
echo "========================================"
cat "$OUTPUT_FILE"
echo "========================================"
