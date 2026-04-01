#!/usr/bin/env bash
# 模块：应用安装

MENU_TITLE="应用安装"
MENU_ITEMS=(
    "安装 Docker"
    "安装 Caddy"
)

menu_apps() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_install_docker ;;
            2) cmd_install_caddy ;;
        esac
        press_any_key
    done
}

# ── Docker ──────────────────────────────────────────────────

cmd_install_docker() {
    require_root
    title "安装 Docker"

    if has_cmd docker; then
        local ver
        ver=$(docker --version 2>/dev/null)
        warn "Docker 已安装：${ver}"
        confirm "是否重新安装/升级？" || return
    fi

    detect_os

    # Alpine 单独处理
    if [[ "$OS_ID" == "alpine" ]]; then
        info "Alpine：使用 apk 安装..."
        apk update && apk add docker docker-compose
        rc-update add docker default
        service docker start
    else
        info "使用官方脚本安装（get.docker.com）..."
        curl -fsSL https://get.docker.com | sh
    fi

    # 启动并设置开机自启
    if has_cmd systemctl; then
        systemctl enable --now docker
    fi

    # 将当前登录用户加入 docker 组（非 root 场景）
    local login_user="${SUDO_USER:-}"
    if [[ -n "$login_user" && "$login_user" != "root" ]]; then
        usermod -aG docker "$login_user"
        info "已将 ${login_user} 加入 docker 组，重新登录后生效"
    fi

    echo
    success "Docker 安装完成"
    docker --version
    echo
    info "常用命令："
    echo -e "  docker ps          # 查看运行中容器"
    echo -e "  docker compose up  # 启动 compose 项目"
}

# ── Caddy ───────────────────────────────────────────────────

cmd_install_caddy() {
    require_root
    title "安装 Caddy"

    if has_cmd caddy; then
        local ver
        ver=$(caddy version 2>/dev/null)
        warn "Caddy 已安装：${ver}"
        confirm "是否重新安装/升级？" || return
    fi

    detect_os
    detect_pkg_manager

    case "$PKG_MANAGER" in
        apt)
            info "Debian/Ubuntu：添加官方源..."
            apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/setup.deb.sh' | bash
            apt-get install -y caddy
            ;;
        dnf|yum)
            info "RHEL/CentOS：添加官方源..."
            "$PKG_MANAGER" install -y 'dnf-command(copr)' 2>/dev/null || true
            "$PKG_MANAGER" copr enable -y @caddy/caddy 2>/dev/null || \
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/rpm.repo' \
                    | tee /etc/yum.repos.d/caddy.repo
            "$PKG_MANAGER" install -y caddy
            ;;
        *)
            # 兜底：下载预编译二进制
            info "使用预编译二进制安装..."
            _caddy_install_binary
            ;;
    esac

    # 启动并开机自启
    if has_cmd systemctl; then
        systemctl enable --now caddy
    fi

    # 写入最基础的 Caddyfile（如果不存在）
    local caddyfile="/etc/caddy/Caddyfile"
    if [[ ! -f "$caddyfile" ]]; then
        mkdir -p /etc/caddy
        cat > "$caddyfile" << 'EOF'
# Caddy 配置文件
# 文档：https://caddyserver.com/docs/caddyfile

:80 {
    respond "Caddy is running!"
}
EOF
        info "已创建默认配置：${caddyfile}"
    fi

    echo
    success "Caddy 安装完成"
    caddy version
    echo
    info "配置文件：${caddyfile}"
    info "常用命令："
    echo -e "  systemctl reload caddy   # 热重载配置"
    echo -e "  caddy validate           # 验证 Caddyfile 语法"
    echo -e "  caddy fmt --overwrite    # 格式化 Caddyfile"
}

# 二进制安装兜底（用于不支持包管理器的系统）
_caddy_install_binary() {
    detect_arch
    local bin_arch
    case "$ARCH" in
        amd64) bin_arch="amd64" ;;
        arm64) bin_arch="arm64" ;;
        armv7) bin_arch="armv7" ;;
        *)     die "不支持的架构：${ARCH}" ;;
    esac

    info "获取最新版本号..."
    local version
    version=$(curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"\(v[^"]*\)".*/\1/')
    [[ -z "$version" ]] && die "无法获取 Caddy 版本信息"

    local url="https://github.com/caddyserver/caddy/releases/download/${version}/caddy_${version#v}_linux_${bin_arch}.tar.gz"
    info "下载 Caddy ${version} (${bin_arch})..."

    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "${tmp}/caddy.tar.gz"
    tar -xzf "${tmp}/caddy.tar.gz" -C "$tmp"
    install -m 755 "${tmp}/caddy" /usr/local/bin/caddy
    rm -rf "$tmp"

    # 创建 systemd 服务
    if has_cmd systemctl; then
        useradd -r -s /sbin/nologin caddy 2>/dev/null || true
        mkdir -p /etc/caddy /var/log/caddy
        chown caddy:caddy /var/log/caddy
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.service" \
            -o /etc/systemd/system/caddy.service
        systemctl daemon-reload
    fi
}
