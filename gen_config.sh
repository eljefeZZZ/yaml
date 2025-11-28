#!/bin/bash

# ================= 配置区域 =================
# 1. GitHub 模板 RAW 地址 (请确保你的 YAML 模板里 proxy-providers 下面有一个名为 Airport 的默认配置)
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

echo -e "${BLUE}🧹 [系统] 正在清理旧文件...${PLAIN}"
rm -f *.tmp vmess_parser.py "$OUTPUT_FILE" provider_block.tmp group_insert.tmp

# ... (此处省略 vmess_parser.py 生成代码，和原来一样) ...
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ 未检测到 Python3，链接转换功能不可用。${PLAIN}"
fi
cat << 'EOF' > vmess_parser.py
import sys, base64, json, urllib.parse
# ... (保持原有的 python 代码不变) ...
EOF

echo -e "${BLUE}⬇️ [网络] 正在下载配置模板...${PLAIN}"
curl -s -o template.tmp "${TEMPLATE_URL}?t=$(date +%s)"

if ! grep -q "proxies:" template.tmp; then
    echo -e "${RED}❌ 错误：下载的文件不是有效的 YAML 模板。${PLAIN}"
    exit 1
fi

# =======================================================
# 🚀 核心增强：循环添加多机场订阅
# =======================================================
echo "========================================"
echo -e "${CYAN}📡 机场订阅配置 (支持添加多个)${PLAIN}"

# 初始化变量
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
        
        # 生成 Provider 配置块
        # 注意：这里使用了 EOF 块来生成规范的 YAML 格式
        # path 设为不同的文件，防止冲突
        providers_yaml="${providers_yaml}  ${provider_name}:\n    type: http\n    url: \"${sub_url}\"\n    path: ./proxies/airport_${count}.yaml\n    interval: 86400\n    health-check:\n      enable: true\n      interval: 600\n      url: http://www.gstatic.com/generate_204\n\n"
        
        # 生成策略组 use 列表
        group_use_yaml="${group_use_yaml}      - ${provider_name}\n"
        
        echo -e "${GREEN}✅ 已添加: ${provider_name}${PLAIN}"
    else
        echo -e "${RED}❌ 链接为空，跳过。${PLAIN}"
    fi
done

# --- 将生成的 Provider 插入到模板 ---
if [ $count -gt 0 ]; then
    echo -e "${BLUE}⚙️ 正在注入 ${count} 个机场配置...${PLAIN}"
    
    # 1. 替换 proxy-providers 下面的默认 Airport
    # 技巧：先把默认的 Airport 块删掉（假设模板里是标准的缩进格式），或者直接在 proxy-providers: 下面插入
    # 这里我们采用更粗暴有效的方法：直接覆盖默认的 Airport 占位符
    # 假设模板里有一行是 "  Airport:"，我们用 sed 把它和后面的几行替换掉，或者直接在 proxy-providers: 后追加
    
    # 为了稳妥，我们先删除模板里原有的 Airport 示例（如果有的话）
    # 假设模板里的示例叫 "  Airport:"
    sed -i '/^  Airport:/,+8d' template.tmp
    
    # 在 proxy-providers: 行的下一行插入我们生成的所有 providers
    # 使用 awk 或者 sed 插入。这里用 sed 在特定行后追加
    sed -i "/^proxy-providers:/a\\${providers_yaml}" template.tmp
    
    # 2. 将新机场加入策略组 (寻找 use: 下面的 - Airport 并替换)
    # 先删掉模板里旧的 "- Airport"
    sed -i '/- Airport/d' template.tmp
    
    # 在所有 "    use:" 的下一行插入我们要加的列表
    # 这里的逻辑是：只要看到 use: 就把所有机场插进去
    sed -i "/^    use:/a\\${group_use_yaml}" template.tmp
    
    echo -e "${GREEN}✅ 多机场配置注入完成。${PLAIN}"
else
    echo -e "${CYAN}ℹ️ 未添加任何机场，保留默认配置。${PLAIN}"
fi

# =======================================================
# ... (后续的自动节点生成逻辑保持不变) ...
# ... (从 "echo -e "${BLUE}🔍 [处理] 读取本机自动节点信息...${PLAIN}" 开始) ...

# (把原来脚本剩下的部分贴在这里)
# ...
