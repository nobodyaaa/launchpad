# Launchpad - Local Services Manager

## 项目说明

统一管理本地服务的 Web 控制面板。任何可以用 `start.sh` 启动、`stop.sh` 停止的服务都可以接入，不限于 Docker。

- **server.py** — Python 后端（零依赖，仅用标准库）
- **index.html** — 前端管理界面
- **services.json** — 已注册的服务列表
- **launch.sh** — CLI 入口（安装为 `lp` 命令）

### 全局命令（lp）

```bash
# 安装
bash launch.sh install    # → ~/.local/bin/lp

# 面板控制
lp start                  # 启动 Web 面板 http://localhost:9999
lp stop                   # 停止面板
lp status                 # 查看面板状态
lp restart                # 重启面板

# 服务管理
lp list                   # 列出所有服务
lp run <id>               # 启动服务
lp stop <id>              # 停止服务
lp register <name> <path> # 注册新服务
```

添加服务使用 `/launchpad` 命令或 `lp register` 即可。

## 服务类型

- **Docker 服务**：目录下有 `docker-compose.yml`/`.yaml` → 支持状态检测、容器列表、端口显示、日志查看
- **通用服务**：没有 docker-compose 文件 → 仅提供启停功能，状态显示 `—`，日志不可用

## 添加新服务的流程

当用户给了一个项目路径时：

### 1. 创建启动/停止脚本

在项目目录下的 `.launchpad/` 目录中创建 `start.sh` 和 `stop.sh`，确保可执行（`chmod +x`）：

```
project/
├── .launchpad/
│   ├── start.sh
│   └── stop.sh
├── docker-compose.yml（可能没有）
└── ...
```

**start.sh** — 启动服务的脚本（使用 `cd "$(dirname "$0")/.."` 回到项目根目录）
**stop.sh** — 停止服务的脚本

两个脚本都必须写，缺一不可。

### 2. 注册到管理中心

编辑 `services.json`，按已有格式添加新服务：

```json
{
  "service-id": {
    "label": "显示名称",
    "icon": "图标 emoji",
    "path": "/absolute/path/to/service",
    "url": "http://localhost:5678",
    "description": "简短描述"
  }
}
```

或者通过 Web 界面点 "+ Add Service" 添加。

### 3. 验证

- 刷新管理页面，确认新服务正确显示
- 确认 `has_start_script` 和 `has_stop_script` 均为 true
- 点击 Start/Stop 测试启停功能

## 核心规则

- 启停只认 `.launchpad/start.sh` / `.launchpad/stop.sh`，不兜底任何其他方式
- 脚本不存在时页面会显示警告并禁用按钮
- 前端和后端均在本地运行（127.0.0.1:9999）
