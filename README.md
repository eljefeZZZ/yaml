🚀 ElJefe-V2 & Clash Config Auto-Generator
[![V2Ray](https://img.shields.io/badge/Project-V2Ray-blue?style=flat-
[

一键部署 V2Ray 服务端 + 一键生成 Clash 客户端配置

告别繁琐的手动填参！本项目提供了一套完整的 VPS 科学上网解决方案：从 Reality/VLESS/VMess 协议的自动部署，到完美适配 Mihomo 内核的 YAML 配置文件生成，全程自动化处理。

✨ 核心特性 (Features)
🔌 无缝对接部署脚本：专为配套的 V2Ray 部署脚本设计，自动读取 UUID、Key 等核心参数，无需人工干预。

🛠️ 智能 YAML 生成：

自动拉取远程通用模板，保持规则实时更新。

自动填充 Reality (推荐)、VLESS-CDN、VMess-CDN 三种协议节点。

独家功能：支持 交互式添加外部 Vmess 链接，自动解析并合并到策略组中。

🎨 极致体验：

脚本输出带有 ANSI 颜色高亮，关键信息一目了然。

支持 机场订阅一键替换，自动修改配置文件中的订阅地址。

🛡️ 安全隐私：

代码数据分离：敏感信息（UUID/Key）仅在 VPS 本地读取，脚本代码不含任何硬编码隐私数据。

自动清理：运行结束后自动删除所有临时文件，保持系统洁净。

⚙️ 兼容性优化：生成的 YAML 完美适配 Mihomo (Clash Meta) 内核，直接启用 Reality 协议支持。

📦 第一步：部署 V2Ray 服务端
💡 说明：这是基础环境，必须先在 VPS 上运行此脚本安装 V2Ray 服务。

请连接到你的 VPS（推荐 Debian 10+/Ubuntu 20+），执行以下命令：

```
bash
wget -O setup.sh https://github.com/eljefeZZZ/v2ray/raw/refs/heads/main/setup.sh && sed -i 's/\r$//' setup.sh && chmod +x setup.sh && ./setup.sh
```

部署脚本功能：

✅ 自动申请 SSL 证书

✅ 部署 Nginx 伪装站

✅ 启用 BBR 加速

✅ 生成 UUID 和 Reality 密钥对

📑 第二步：一键生成 Clash 配置
💡 说明：当第一步安装完成后，运行此脚本即可立即获得一个**“拿来即用”**的 YAML 配置文件。

🚀 运行生成命令

```
bash
bash <(curl -sL https://raw.githubusercontent.com/eljefeZZZ/yaml/main/gen_config.sh)
```

🕹️ 脚本运行流程
自动检测：脚本会自动读取 setup.sh 生成的配置信息。

订阅询问：询问是否需要填入机场订阅链接（支持整行自动替换）。

节点合并：

自动生成本机 Reality/VLESS/VMess 节点。

询问是否粘贴外部 vmess:// 链接（支持批量添加备用节点）。

生成结果：在 /root/clash_final.yaml 生成最终文件。

结果交付：提供 Transfer.sh 下载链接 或 直接打印内容 供复制。

⚠️ 特别注意事项
1. 关于 Reality 协议与内核兼容性
本脚本生成的 YAML 配置文件中包含了 Reality 协议 的节点信息（client-fingerprint, reality-opts 等字段）。

✅ 推荐客户端：请使用支持 Mihomo (原 Clash Meta) 内核的客户端（如 Clash Verge Rev, Clash Meta for Android 等）。

❌ 普通客户端：如果你使用的是原版 Clash Premium 或未更新内核的 Clash for Windows，请务必手动删除 YAML 文件中的 Reality 节点，否则会导致配置文件加载失败。

2. 手动节点持久化
脚本会在 /root/manual_nodes.yaml 保存你手动添加的外部节点。

保留机制：再次运行脚本时，会询问是否保留这些旧节点，无需重复添加。

去重建议：如果更换了外部节点，建议选择“清空旧节点”重新添加。

📂 文件结构说明
文件名	作用	备注
setup.sh	V2Ray 服务端安装脚本	核心环境部署
gen_config.sh	Clash 配置生成器	逻辑处理核心
clash_template_pro.yaml	通用规则模板	托管于 Gist，含分流规则
/root/clash_final.yaml	最终产物	直接导入客户端使用
🤝 贡献与反馈
如果你在使用过程中遇到问题，或者有新的功能建议，欢迎提交 Issue 或 Pull Request。

Bug 反馈：请附上脚本运行时的报错截图（注意打码敏感 IP）。

功能建议：欢迎提供更多协议的解析支持（如 VLESS 链接解析）。

Made with ❤️ for better internet experience.
