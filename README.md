<p align="center">
  <img src="assets/logos/logo_ou-sb_project-mark_20260802_square.jpg" width="180" alt="OU-SB Logo">
</p>

<h1 align="center">OU-SB</h1>

<p align="center">简洁、可增删协议的 sing-box 一键管理脚本</p>

<p align="center"><strong>作者：nodeseek @cshaizhihao</strong></p>

## 功能

- SS2022、Hysteria2、TUIC、VLESS Reality、AnyTLS Reality
- VLESS 默认 TCP + XTLS Vision + Reality
- 已有协议不重装，随时添加或单独删除其他协议
- Hysteria2 自定义 UDP 端口跳跃
- Snell v4/v5/v6 实验支持（按需安装 sing-box testing 版本）
- 配置校验、自动备份和失败回滚

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cshaizhihao/OU-SB/main/OU-SB.sh)
```

## 使用

```bash
sb
```

HY2 端口跳跃启用后，请在服务器安全组放行对应 UDP 端口或范围。

## 系统

Debian / Ubuntu / Rocky Linux / AlmaLinux / CentOS Stream / Alpine Linux

## License

[MIT](LICENSE)
