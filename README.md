# Codex Relay Station

将 ChatGPT Plus 订阅转换为 OpenAI 兼容 API，分享给朋友使用的中转站方案。

## 架构

```
用户 (API Key) -> New API (port 3000) -> chat2api (port 5005) -> OpenAI
                     ↑ 管理面板              ↑ 协议转换
```

- **New API** — 中转站管理面板，负责用户管理、额度控制、API Key 分发
- **chat2api** — 将 ChatGPT Web 会话转换为标准 OpenAI API 格式

## 支持模型

gpt-4o, gpt-4o-mini, gpt-5.5, o1, o1-mini, o3, o3-mini, o4-mini

## 系统要求

- Ubuntu 22.04+ (推荐)
- 1 核 CPU, 1GB 内存 (最低)
- 10GB 磁盘空间
- 海外 VPS (需要直连 OpenAI)
- ChatGPT Plus 订阅 ($20/月)

## 快速部署

### 一键部署

```bash
# 下载部署脚本
git clone https://github.com/xiaoci63/codex-relay-station.git
cd codex-relay-station

# 运行部署 (需要 root 权限)
chmod +x scripts/deploy.sh
sudo ./scripts/deploy.sh
```

部署完成后会自动：
- 安装 Docker 和 Docker Compose
- 配置防火墙 (UFW) 和 SSH 安全加固
- 部署 New API 和 chat2api 容器
- 将 SSH 端口改为 28953

### 配置 ChatGPT 渠道

```bash
# 获取 ChatGPT access token
# 浏览器登录后访问: https://chatgpt.com/api/auth/session
# 复制 accessToken 的值

# 运行渠道配置脚本
chmod +x scripts/setup-channel.sh
sudo ./scripts/setup-channel.sh
```

### 手动部署 (Docker Compose)

```bash
# 启动服务
docker compose up -d

# 等待 10 秒后访问面板
# http://YOUR_IP:3000
# 默认账号: root / 123456
```

## 使用方式

给朋友分发 API Key 后，他们在任意兼容客户端配置：

| 配置项 | 值 |
|--------|-----|
| API Base URL | `http://YOUR_SERVER_IP:3000/v1` |
| API Key | `sk-xxxxxxxxxx` (分配的密钥) |
| 可用模型 | gpt-4o, gpt-4o-mini, gpt-5.5, o1, o1-mini, o3, o3-mini, o4-mini |

### 兼容客户端

- [ChatBox](https://chatboxai.app/)
- [ChatGPT-Next-Web](https://github.com/ChatGPTNextWeb/ChatGPT-Next-Web)
- [Lobe Chat](https://lobehub.com/)
- [Cherry Studio](https://cherrystudio.com/)
- [OpenCat](https://opencat.app/)

## 用户管理

### 创建用户

登录管理面板 (http://YOUR_IP:3000) → 用户管理 → 新增用户

### 分配额度

在管理面板中编辑用户，设置 quota 值：
- 500,000 单位 = $1 等额
- 建议每个用户分配 $5 (2,500,000 单位)

### 生成 API Key

管理面板 → 令牌管理 → 新增令牌 → 选择对应用户

## 安全配置

部署脚本会自动配置以下安全措施：

- SSH 端口从 22 改为 28953
- fail2ban 防暴力破解 (3次失败封禁24小时)
- UFW 防火墙仅开放必要端口
- 默认关闭公开注册

## 维护

### 更新 Access Token

ChatGPT 的 access token 会过期，需要定期更新：

```bash
# 获取新 token 后更新数据库
sqlite3 /opt/relay-station/data/new-api/one-api.db \
  "UPDATE channels SET key = 'NEW_ACCESS_TOKEN' WHERE id = 1;"

# 重启服务
cd /opt/relay-station && docker compose restart new-api
```

### 查看日志

```bash
docker logs new-api --tail 50
docker logs chat2api --tail 50
```

### 添加新模型

需要同时更新三处：

```bash
# 1. channels 表的 models 字段
sqlite3 /opt/relay-station/data/new-api/one-api.db \
  "UPDATE channels SET models = models || ',NEW_MODEL' WHERE id = 1;"

# 2. abilities 表添加映射
sqlite3 /opt/relay-station/data/new-api/one-api.db \
  "INSERT INTO abilities (\`group\`, model, channel_id, enabled, priority, weight, tag) \
   VALUES ('default', 'NEW_MODEL', 1, 1, 10, 0, '');"

# 3. 重启生效
docker restart new-api
```

## 项目结构

```
codex-relay-station/
├── docker-compose.yml          # 合并部署文件
├── docker/
│   ├── new-api/
│   │   └── docker-compose.yml  # New API 独立部署
│   └── chat2api/
│       └── docker-compose.yml  # chat2api 独立部署
├── scripts/
│   ├── deploy.sh               # 一键部署脚本
│   └── setup-channel.sh        # 渠道配置脚本
├── config/
│   ├── daemon.json             # Docker 守护进程配置
│   ├── fail2ban-jail.local     # fail2ban 配置
│   ├── sshd_config.sample      # SSH 配置示例
│   └── ufw-rules.txt           # 防火墙规则
└── README.md
```

## 常见问题

**Q: API 返回 "upstream error: connection refused"**
A: New API 容器内不能访问 `localhost:5005`，需要将渠道的 base_url 改为 `http://172.17.0.1:5005` (Docker 网关地址)。

**Q: 创建渠道时报 panic 错误**
A: New API v1.0.0-rc.15 的 API 创建渠道有 bug，需要通过 SQLite 直接插入数据库。

**Q: 提示 "模型价格未配置"**
A: 在数据库中设置自用模式：`sqlite3 one-api.db "INSERT OR REPLACE INTO options (key, value) VALUES ('SelfUseModeEnabled', 'true');"`

**Q: 用户额度不足**
A: 需要同时设置用户的 quota 和 token 的 remain_quota 字段。

## License

MIT
