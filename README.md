# runit

服务器一键脚本工具集，纯 Shell 实现，零依赖。

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/allo-rs/runit/main/runit.sh)
```

或者安装到系统（需要 root）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/allo-rs/runit/main/install.sh)
# 安装后直接运行
runit
```

## 功能模块

| 模块 | 功能 |
|------|------|
| 系统信息 | 系统概览、CPU/内存/磁盘/网络接口、进程负载 |
| 网络工具 | IP 查询、连通性测试、端口检测、DNS、测速、路由追踪 |
| 安全配置 | SSH 加固、防火墙、fail2ban（开发中） |
| 应用安装 | Docker、Nginx、BBR 加速等（开发中） |
| 系统优化 | 换源、时区、内核参数（开发中） |

## 命令行直接运行子模块

```bash
# 直接进入某个模块，跳过主菜单
bash <(curl -fsSL https://raw.githubusercontent.com/allo-rs/runit/main/runit.sh) system
bash <(curl -fsSL https://raw.githubusercontent.com/allo-rs/runit/main/runit.sh) network
```

## 兼容性

- Debian / Ubuntu
- CentOS / RHEL / Rocky / AlmaLinux
- Alpine
- Arch Linux
- macOS（部分功能）

需要 `bash 4+` 和 `curl`。

## 项目结构

```
runit/
├── runit.sh              # 主入口 + 菜单引擎
├── install.sh            # 系统安装脚本
├── lib/
│   ├── ui.sh             # 颜色、菜单渲染
│   ├── sys.sh            # OS/架构/包管理器检测
│   └── utils.sh          # 通用工具函数
└── modules/
    ├── 01-system/        # 系统信息
    ├── 02-network/       # 网络工具
    ├── 03-security/      # 安全配置
    ├── 04-apps/          # 应用安装
    └── 05-optimize/      # 系统优化
```

## 添加自定义模块

1. 在 `modules/` 下新建目录，如 `06-custom/`
2. 创建 `menu.sh`，实现 `menu_xxx()` 函数
3. 在 `runit.sh` 主菜单数组中注册

参考 `modules/01-system/menu.sh` 的结构。

## License

MIT
