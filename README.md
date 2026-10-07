<p align="center"><img src="assets/logos/logo_ou-sb-v2.0.0.png" width="240" alt="OU-SB Logo"></p>
<h1 align="center">OU-SB · V2.0.0</h1>
<p align="center"><strong>SSH 中的一键 sing-box 安装与多协议管理工具</strong></p>
<p align="center">🚀 快速安装　🌈 国旗节点名　🧰 自动备份　📶 BBR + FQ 调优</p>

## 📌 这是什么

OU-SB 面向需要在 SSH 中快速部署 sing-box 的用户。脚本会检测系统、安装 sing-box、创建服务、生成协议入站、输出客户端链接，并保留非 OU-SB 管理的配置。

V2.0.0 的交互重点是：首次运行按推荐值一路回车即可完成部署；协议名称默认使用“国旗 + 空格 + 协议名”，也可以在添加时自定义。

## ⚡ 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cshaizhihao/OU-SB/main/OU-SB.sh)
```

首次运行流程：

1. 输入大写 `YES` 确认脚本将管理 sing-box、服务和防火墙；
2. 自动检测公网 IP，也可以输入自己的 IP 或 DDNS；
3. 检测 BBR + FQ，回车进入 TCP 调优；
4. TCP 缓冲区选择推荐值、预设 MB 或自定义 MB；
5. 添加协议，直接回车默认选择 VLESS TCP + Vision + Reality；
6. 设置协议名称并启动服务。

> 支持 Debian、Ubuntu、Rocky Linux、AlmaLinux、CentOS Stream 和 Alpine。建议使用 root 在全新服务器上运行，并提前放行安全组端口。

## 🔌 支持协议

- VLESS TCP + XTLS Vision + Reality
- Shadowsocks 2022
- Hysteria2（UDP 端口跳跃）
- TUIC
- AnyTLS Reality
- Trojan TLS
- Snell v4/v5/v6（实验）

所有 OU-SB 入站使用 `ou-sb-*` tag。删除 OU-SB 协议时，其他入站会被保留。

## 🧭 使用方式

安装完成后直接输入：

```bash
sb
```

主菜单提供节点配置、协议添加/删除、端口修改、HY2 端口跳跃、服务启停、BBR + FQ 与 TCP 调优、更新和卸载。

常用命令：

```bash
sb --status
sb --validate
sb --backup
sb --export
sb --doctor
```

## 🌈 节点名称

脚本会尝试通过多个公网 IP 服务检测服务器地址，再根据国家代码生成国旗。默认名称示例：

```text
🇺🇸 VLESS
🇸🇬 SS2022
🇯🇵 Trojan
🌐 TUIC
```

如果公网 IP 服务不可用，会回退到本机地址或 `🌐`；也可以在“节点信息”中手动填写 IP、DDNS 或自定义名称。

## 📶 BBR + FQ 与 TCP 调优

首次安装会自动检测当前拥塞控制和队列调度。网络优化菜单支持：

- 开启 BBR + FQ；
- 切换回 cubic；
- 根据内存使用推荐 MB；
- 选择 4/8/16/32 MB 预设；
- 手动输入 1-1024 MB。

配置保存到 `/etc/sysctl.d/99-ou-sb-network.conf`。

## 🔐 安全和恢复

- 配置变更前自动备份配置和状态；
- 失败校验不会覆盖旧配置；
- 私钥、配置和状态文件使用受限权限；
- Alpine 下载 sing-box 时校验 SHA-256；
- 卸载时可选择是否删除 sing-box 程序和残留。

## 🧪 开发测试

```bash
bash -n OU-SB.sh tests/test.sh
bash tests/test.sh
```

## 📄 License

[MIT](LICENSE)
