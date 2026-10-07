<p align="center">
  <img src="assets/logos/logo_ou-sb-v2.2.0.png" width="240" alt="OU-SB V2 Logo">
</p>

<h1 align="center">OU-SB · v2.2.0</h1>

<p align="center"><strong>面向 SSH 的 sing-box 一键安装与多协议管理工具</strong></p>

<p align="center">🚀 安装更稳　🔐 更新可校验　🧰 配置可恢复　🌐 协议可扩展</p>

<p align="center">
  <a href="https://github.com/cshaizhihao/OU-SB/actions"><img src="https://github.com/cshaizhihao/OU-SB/actions/workflows/shellcheck.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-2.0.0-2f80ed?style=flat-square" alt="version">
  <img src="https://img.shields.io/badge/sing--box-supported-111827?style=flat-square" alt="sing-box">
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT">
</p>

## ✨ 项目定位

OU-SB 是一个在 SSH 终端中运行的 sing-box 服务端管理工具。它负责安装运行环境、生成协议入站、管理证书和端口、输出客户端连接信息，并在配置变更前自动校验和备份。

V2.2.0 重点强化了“首次安装、日常维护、故障恢复”三条路径：适合新服务器快速部署，也适合已有 sing-box 配置的谨慎接管。

## ⚡ 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cshaizhihao/OU-SB/main/OU-SB.sh)
```

首次运行会：

1. 检测发行版、架构、服务管理器和基础依赖；
2. 安装或检查 sing-box；
3. 创建受限权限的数据、证书和备份目录；
4. 保留非 `ou-sb-*` 入站，不会静默覆盖已有配置；
5. 写入 systemd 或 OpenRC 服务；
6. 配置协议并在应用前执行配置校验。

> 建议使用全新 Debian、Ubuntu、Rocky Linux、AlmaLinux、CentOS Stream 或 Alpine 服务器，并以 root 运行。生产环境请先确认安全组和防火墙策略。

## 🧩 已支持协议

- Shadowsocks 2022
- Hysteria2（可选 UDP 端口跳跃）
- TUIC
- VLESS TCP + XTLS Vision + Reality
- AnyTLS Reality
- Trojan TLS（使用本地或导入证书）
- Snell v4/v5/v6（实验功能）

协议配置使用独立 `ou-sb-*` tag。删除或卸载 OU-SB 时，其他应用管理的入站会被保留。

## 🛠️ 日常命令

```bash
sb                  # 交互式管理面板
sb --status         # 查看系统、sing-box 和协议状态
sb --validate       # 校验配置与状态
sb --backup         # 创建配置备份
sb --export         # 输出客户端连接信息
sb --doctor         # 检查依赖和配置
sb --version        # 查看当前版本
sb --apply-firewall # 恢复 HY2 端口跳跃规则
sb --clear-firewall # 清理 HY2 端口跳跃规则
sb --version        # 查看版本
```

## 🔐 安全与恢复

V2.2.0 会同时备份配置和状态文件，并默认保留最近 20 组备份（可通过 `OU_SB_BACKUP_KEEP` 调整）。

- 配置变更先生成候选文件，并通过 JSON 校验；
- 配置文件、状态文件和私钥使用受限权限；
- 每次提交配置前创建备份；
- sing-box 下载包在 Alpine 路径执行 SHA-256 校验；
- HY2 跳跃规则使用独立规则表；
- 订阅链接只输出客户端所需的公开凭据，不输出 Reality 私钥。

请将服务器安全组放行实际监听端口；启用 HY2 端口跳跃时，还要放行配置的 UDP 端口范围。

## 🧪 开发与测试

```bash
bash -n OU-SB.sh tests/test.sh
shellcheck -x OU-SB.sh tests/test.sh
bash tests/test.sh
```

## 📄 目录

```text
OU-SB.sh                         主脚本
 tests/test.sh                   Bash 单元测试
 assets/logos/logo_ou-sb-v2.2.0.png  V2.2.0 Logo
 .github/workflows/shellcheck.yml CI
```

## 📜 License

[MIT](LICENSE)
