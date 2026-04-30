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
    title "安装 Caddy (含 Cloudflare DNS 插件)"

    if has_cmd caddy; then
        local ver
        ver=$(caddy version 2>/dev/null)
        warn "Caddy 已安装：${ver}"
        confirm "是否重新安装/升级？" || return
    fi

    # 所有平台统一走 Caddy 官方 API 下载含 CF 插件的定制二进制
    _caddy_install_binary

    # ── Cloudflare API Token ───────────────────────────────────
    local cf_token
    echo
    info "Cloudflare DNS 插件需要 API Token 方可使用 DNS 验证 SSL"
    info "Token 权限要求：Zone / DNS / Edit（推荐使用 Zone 范围 Token）"
    read -rsp "$(echo -e "${CYAN}Cloudflare API Token (留空跳过): ${NC}")" cf_token
    echo

    mkdir -p /etc/caddy
    local env_file="/etc/caddy/caddy.env"
    if [[ -n "$cf_token" ]]; then
        echo "CLOUDFLARE_API_TOKEN=${cf_token}" > "$env_file"
        chmod 600 "$env_file"
        success "Token 已写入 ${env_file}"
    else
        warn "未配置 Token，后续可手动写入：${env_file}"
        touch "$env_file"
        chmod 600 "$env_file"
    fi

    # ── 创建 caddy 用户与目录 ──────────────────────────────────
    id -u caddy &>/dev/null || useradd -r -s /sbin/nologin caddy
    mkdir -p /etc/caddy /var/log/caddy /var/lib/caddy
    chown caddy:caddy /var/log/caddy /var/lib/caddy

    # ── 启动并开机自启 ─────────────────────────────────────────
    if has_cmd rc-service; then
        # Alpine / OpenRC：将 Token 写入 /etc/conf.d/caddy
        mkdir -p /etc/conf.d
        [[ -n "$cf_token" ]] && echo "CLOUDFLARE_API_TOKEN=${cf_token}" > /etc/conf.d/caddy
        rc-update add caddy default 2>/dev/null || true
        if rc-service caddy status 2>/dev/null | grep -q started; then
            rc-service caddy restart
        else
            rc-service caddy start
        fi
    elif has_cmd systemctl; then
        # systemd：官方 service 已含 EnvironmentFile=-/etc/caddy/caddy.env
        systemctl daemon-reload
        systemctl enable --now caddy
    fi

    # ── 写入默认 Caddyfile ─────────────────────────────────────
    local caddyfile="/etc/caddy/Caddyfile"
    if [[ ! -f "$caddyfile" ]]; then
        cat > "$caddyfile" << 'EOF'
# Caddy 配置文件 - 含 Cloudflare DNS 插件
# 文档：https://caddyserver.com/docs/caddyfile

# ── 示例：Cloudflare DNS 验证泛域名证书 ──────────────────────
# your.domain.com {
#     tls {
#         dns cloudflare {env.CLOUDFLARE_API_TOKEN}
#     }
#     reverse_proxy localhost:8080
# }
#
# *.your.domain.com {
#     tls {
#         dns cloudflare {env.CLOUDFLARE_API_TOKEN}
#     }
#     reverse_proxy localhost:8080
# }

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
    info "Token 文件：${env_file}"
    info "常用命令："
    echo -e "  systemctl reload caddy   # 热重载配置"
    echo -e "  caddy validate           # 验证 Caddyfile 语法"
    echo -e "  caddy fmt --overwrite    # 格式化 Caddyfile"
}

# 从 Caddy 官方 Download API 下载含 Cloudflare DNS 插件的定制二进制
_caddy_install_binary() {
    detect_arch
    local bin_arch
    case "$ARCH" in
        amd64) bin_arch="amd64" ;;
        arm64) bin_arch="arm64" ;;
        armv7) bin_arch="armv7" ;;
        *)     die "不支持的架构：${ARCH}" ;;
    esac

    local plugin="github.com/caddy-dns/cloudflare"
    local api_url="https://caddyserver.com/api/download?os=linux&arch=${bin_arch}&p=${plugin}"
    info "从 Caddy 官方 API 下载定制二进制 (含 cloudflare-dns 插件, ${bin_arch})..."

    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$api_url" -o "${tmp}/caddy" || die "下载失败，请检查网络"
    install -m 755 "${tmp}/caddy" /usr/local/bin/caddy
    rm -rf "$tmp"

    # 部署 systemd 服务（官方 caddy.service 已含 EnvironmentFile=-/etc/caddy/caddy.env）
    if has_cmd systemctl && [[ ! -f /etc/systemd/system/caddy.service ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.service" \
            -o /etc/systemd/system/caddy.service
        systemctl daemon-reload
    fi

    # OpenRC 服务（Alpine）
    if has_cmd rc-service && [[ ! -f /etc/init.d/caddy ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.openrc" \
            -o /etc/init.d/caddy 2>/dev/null || true
        chmod +x /etc/init.d/caddy 2>/dev/null || true
    fi
}
