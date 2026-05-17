# 🚀 Launchpad

统一管理本地服务的 Web 控制面板。任何可以用 `start.sh` 启动、`stop.sh` 停止的服务都可以接入，不限于 Docker。

[![GitHub](https://img.shields.io/badge/GitHub-nobodyaaa/launchpad-181717?logo=github)](https://github.com/nobodyaaa/launchpad)

## 快速开始

```bash
python3 server.py
```
或后台运行：
```bash
bash launch.sh start
```

打开 http://localhost:9999

## 特性

- **一键启停** — 任何本地服务，只需 start.sh / stop.sh
- **Docker 集成** — 自动检测容器状态、端口映射、查看日志
- **通用服务** — 不依赖 Docker，支持任意进程
- **实时状态** — 每 15 秒自动刷新，运行/停止一目了然
- **AI 辅助添加** — Claude Code 的 `/launchpad` 命令交互式添加服务

## 工作原理

每个服务的 `.launchpad/` 目录下需要两个脚本：

| 脚本 | 用途 | 必需 |
|------|------|------|
| `.launchpad/start.sh` | 启动服务 | ✅ |
| `.launchpad/stop.sh` | 停止服务 | ✅ |

脚本不存在时，页面会显示警告并禁用操作按钮。

### 服务类型

**Docker 服务** — 目录下有 `docker-compose.yml` 或 `.yaml`
- 自动检测容器状态、端口映射
- 支持查看容器日志

**通用服务** — 没有 docker-compose 文件
- 仅提供启停功能
- 状态显示 `—`

## 添加新服务

1. 在项目目录下创建 `.launchpad/start.sh` 和 `.launchpad/stop.sh`（`chmod +x`）
2. 在 Web 界面点 **+ Add Service**，填入路径即可
3. 也可以直接编辑 `services.json`
4. 或者用 `/launchpad` 命令让 AI 帮你添加

## Claude Code Skill 安装

在 Claude Code 中使用 `/launchpad` 命令可以交互式添加新服务：

```bash
# 1. 克隆项目
git clone https://github.com/nobodyaaa/launchpad.git
cd launchpad

# 2. 安装 skill
mkdir -p ~/.claude/skills/launchpad
cp SKILL.md ~/.claude/skills/launchpad/SKILL.md

# 3. 编辑 SKILL.md，将 PROJECT_DIR 路径改为你的实际路径
#    vim ~/.claude/skills/launchpad/SKILL.md
#    搜索 /home/azyuli/projects/launchpad 替换为你的路径

# 4. 启动面板
bash launch.sh start
```

安装后在 Claude Code 会话中输入 `/launchpad` 即可使用。

## 文件结构

```
launchpad/
├── server.py        # Python 后端（零依赖）
├── index.html       # 管理界面
├── services.json    # 服务注册配置
├── launch.sh        # 后台启动/停止脚本
├── SKILL.md         # Claude Code skill 定义
├── CLAUDE.md        # 项目开发约定
└── README.md        # 本文件
```
