#!/bin/bash

# ==============================================================
# Clash 配置生成神器 (v10.1 智能计数版)
# ==============================================================

# ... (前面的基础配置、颜色定义、辅助函数、初始化、下载模板、机场订阅、生成本机节点代码 保持完全一致) ...
# ... (为了节省篇幅，请保留 v10.0 脚本的前半部分，直接替换下面的第 5 部分) ...

# 1. 基础配置 (为了完整性，还是贴一下头部)
TEMPLATE_URL="https://gist.githubusercontent.com/eljefeZZZ/ec1ea2afe5f4e13e9b01e05ddc11170c/raw/clash_template.yaml"
INFO_FILE="/usr/local/eljefe-v2/info.txt"
MANUAL_NODES_FILE="/root/manual_nodes.yaml"
OUTPUT_FILE="/root/clash_final.yaml"
PORT_REALITY=443
PORT_TLS=8443

# --- 颜色定义 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# --- 辅助函数 ---
function print_title() {
    echo -e "${PURPLE}┌──────────────────────────────────────────────┐${PLAIN}"
    echo -e "${PURPLE}│${PLAIN} ${BOLD}$1${PLAIN}"
    echo -e "${PURPLE}└──────────────────────────────────────────────┘${PLAIN}"
}
function print_step() { echo -e "${BLUE}➜  $1${PLAIN}"; }
function print_success() { echo -e "${GREEN}✔  $1${PLAIN}"; }
function print_error() { echo -e "${RED}✖  $1${PLAIN}"; }

# ... (中间代码省略，请保留 v10.0 的 0~4 步) ...
# ... (这里直接从 第 5 步开始替换) ...

# ===========================================
# 5. 手动节点管理 (智能计数升级)
# ===========================================
echo ""
print_title "🛠️  手动节点管理"
echo -e "${CYAN}提示: 您可以手动添加其他 VMess/VLESS 链接。${PLAIN}"

if [ -f "$MANUAL_NODES_FILE" ] && [ -s "$MANUAL_NODES_FILE" ]; then
    # [智能计数]
    # 统计 vmess:// 链接数量
    VMESS_COUNT=$(grep -c "vmess://" "$MANUAL_NODES_FILE")
    # 统计 yaml 节点数量 (以 - name: 开头)
    YAML_COUNT=$(grep -cE "^[[:space:]]*-[[:space:]]name:" "$MANUAL_NODES_FILE")
    TOTAL_COUNT=$((VMESS_COUNT + YAML_COUNT))
    
    # 如果统计为0但文件有内容，可能是纯文本链接，算作行数
    if [ $TOTAL_COUNT -eq 0 ]; then
        TOTAL_COUNT=$(grep -cve '^\s*$' "$MANUAL_NODES_FILE")
    fi

    read -p "$(echo -e "${YELLOW}❓ 发现 ${BOLD}${TOTAL_COUNT}${PLAIN}${YELLOW} 个旧的手动节点，是否保留？(n=清空) [y/n]: ${PLAIN}")" keep_manual
    if [[ "$keep_manual" == "n" || "$keep_manual" == "N" ]]; then
        echo "" > "$MANUAL_NODES_FILE"
        echo -e "${BLUE}   🗑️  已清空 ${TOTAL_COUNT} 个旧节点${PLAIN}"
    else
        echo -e "${GREEN}   ✔  已保留 ${TOTAL_COUNT} 个旧节点${PLAIN}"
    fi
else
    touch "$MANUAL_NODES_FILE"
    # 文件不存在或为空，无需提示保留
fi

read -p "$(echo -e "${YELLOW}❓ 是否添加新的节点链接？[y/n]: ${PLAIN}")" add_manual
if [[ "$add_manual" == "y" || "$add_manual" == "Y" ]]; then
    echo -e "${GREEN}➜ 请粘贴链接 (vmess://...):${PLAIN}"
    read -r manual_link
    if [[ -n "$manual_link" ]]; then
        echo "$manual_link" >> "$MANUAL_NODES_FILE"
        print_success "链接已保存"
    fi
fi

MANUAL_NODES_TEMP="manual_nodes.tmp"
echo "" > "$MANUAL_NODES_TEMP"

if [ -s "$MANUAL_NODES_FILE" ]; then
    print_step "正在解析手动节点..."
    while read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^#.*$ ]] && continue
        
        if [[ "$line" == vmess://* ]]; then
            RESULT=$(python3 vmess_parser.py "$line")
            if [[ -n "$RESULT" ]]; then
                echo "$RESULT" >> "$MANUAL_NODES_TEMP"
                echo "" >> "$MANUAL_NODES_TEMP"
            else
                print_error "解析失败: ${line:0:20}..."
            fi
        else
            # 普通 YAML 节点，假设是粘贴进来的，手动加缩进
            # 这里做一个简单判断：如果已经是缩进过的就不加了？
            # 为了统一，我们假设用户粘贴的是顶格的 "- name:"
            if [[ "$line" =~ ^- ]]; then
                 echo "  $line" >> "$MANUAL_NODES_TEMP"
            else
                 # 已经是缩进的或者其他属性行
                 echo "  $line" >> "$MANUAL_NODES_TEMP"
            fi
        fi
    done < "$MANUAL_NODES_FILE"
    print_success "手动节点处理完成"
fi

# ===========================================
# 6. 提取名称 & 7. 拼接 (保持不变)
# ===========================================
echo ""
print_step "正在整合所有节点..."
# ... (后续代码保持 v10.0 不变) ...
