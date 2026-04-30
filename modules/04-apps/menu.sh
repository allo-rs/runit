#!/usr/bin/env bash
# 模块：应用安装

MENU_TITLE="应用安装"
MENU_ITEMS=(
    "安装 Docker"
    "安装 Caddy"
    "安装 PostgreSQL (Docker Compose)"
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
            3) cmd_install_postgres ;;
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
    chown caddy:caddy /etc/caddy /var/log/caddy /var/lib/caddy
    chmod 750 /etc/caddy

    # ── 启动并开机自启 ─────────────────────────────────────────
    if has_cmd rc-service; then
        # Alpine / OpenRC：将 Token 写入 /etc/conf.d/caddy
        mkdir -p /etc/conf.d
        if [[ -n "$cf_token" ]]; then
            echo "CLOUDFLARE_API_TOKEN=${cf_token}" > /etc/conf.d/caddy
            chmod 600 /etc/conf.d/caddy
        fi
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
    echo -e "  systemctl reload caddy                              # 热重载配置"
    echo -e "  caddy validate --config ${caddyfile}               # 验证 Caddyfile 语法"
    echo -e "  caddy fmt --overwrite --config ${caddyfile}        # 格式化 Caddyfile"
}

# ── PostgreSQL (Docker Compose) ─────────────────────────────

cmd_install_postgres() {
    require_root
    title "安装 PostgreSQL (Docker Compose)"

    # 检查 Docker
    if ! has_cmd docker; then
        warn "未检测到 Docker，将先安装 Docker..."
        cmd_install_docker
        has_cmd docker || { error "Docker 安装失败，中止"; return 1; }
    fi

    # 检查 docker compose（v2）
    if ! docker compose version &>/dev/null; then
        die "需要 Docker Compose v2（docker compose），请先升级 Docker"
    fi

    # ── 交互配置 ──────────────────────────────────────────────
    local pg_version pg_port pg_password pg_db pg_user pg_data_dir compose_dir

    read -rp "$(echo -e "${CYAN}PostgreSQL 版本 [16]: ${NC}")"    pg_version
    pg_version="${pg_version:-16}"

    read -rp "$(echo -e "${CYAN}监听端口 [5432]: ${NC}")"         pg_port
    pg_port="${pg_port:-5432}"

    # 端口占用检查
    if port_in_use "$pg_port"; then
        warn "端口 ${pg_port} 已被占用"
        confirm "确认仍使用此端口？" || return
    fi

    read -rp "$(echo -e "${CYAN}数据库用户名 [postgres]: ${NC}")" pg_user
    pg_user="${pg_user:-postgres}"

    read -rsp "$(echo -e "${CYAN}数据库密码 (必填): ${NC}")"      pg_password
    echo
    [[ -z "$pg_password" ]] && die "密码不能为空"

    read -rp "$(echo -e "${CYAN}默认数据库名 [postgres]: ${NC}")" pg_db
    pg_db="${pg_db:-postgres}"

    read -rp "$(echo -e "${CYAN}Compose 文件目录 [/opt/postgres]: ${NC}")" compose_dir
    compose_dir="${compose_dir:-/opt/postgres}"
    pg_data_dir="${compose_dir}/data"

    # ── 幂等检查 ──────────────────────────────────────────────
    if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
        warn "检测到已有配置：${compose_dir}/docker-compose.yml"
        confirm "是否覆盖并重新部署？" || return
        docker compose -f "${compose_dir}/docker-compose.yml" down 2>/dev/null || true
    fi

    # ── 写入 docker-compose.yml ───────────────────────────────
    mkdir -p "$compose_dir" "$pg_data_dir"
    cat > "${compose_dir}/docker-compose.yml" << EOF
services:
  postgres:
    image: postgres:${pg_version}-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${pg_user}
      POSTGRES_PASSWORD: ${pg_password}
      POSTGRES_DB: ${pg_db}
      PGDATA: /var/lib/postgresql/data/pgdata
    ports:
      - "${pg_port}:5432"
    volumes:
      - ${pg_data_dir}:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${pg_user} -d ${pg_db}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

    info "配置文件：${compose_dir}/docker-compose.yml"

    # ── 启动服务 ──────────────────────────────────────────────
    info "拉取镜像并启动..."
    docker compose -f "${compose_dir}/docker-compose.yml" up -d

    # 等待健康检查通过（最多 30s）
    info "等待 PostgreSQL 就绪..."
    local i=0
    while ! docker compose -f "${compose_dir}/docker-compose.yml" \
            exec -T postgres pg_isready -U "$pg_user" -d "$pg_db" &>/dev/null; do
        ((i++))
        [[ $i -ge 30 ]] && { warn "健康检查超时，请手动确认容器状态"; break; }
        sleep 1
    done

    echo
    success "PostgreSQL 部署完成"
    echo
    info "连接信息："
    echo -e "  主机：localhost"
    echo -e "  端口：${pg_port}"
    echo -e "  用户：${pg_user}"
    echo -e "  数据库：${pg_db}"
    echo -e "  数据目录：${pg_data_dir}"
    echo
    info "常用命令："
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml ps"
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml logs -f"
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml down"
    echo -e "  psql -h 127.0.0.1 -p ${pg_port} -U ${pg_user} -d ${pg_db}"
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
    install -m 755 "${tmp}/caddy" /usr/bin/caddy
    rm -rf "$tmp"

    # 部署 systemd 服务（官方 caddy.service 已含 EnvironmentFile=-/etc/caddy/caddy.env）
    if has_cmd systemctl && [[ ! -f /etc/systemd/system/caddy.service ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.service" \
            -o /etc/systemd/system/caddy.service
        # 官方 service 未设置 HOME，caddy 无法写入配置自动保存目录
        mkdir -p /etc/systemd/system/caddy.service.d
        cat > /etc/systemd/system/caddy.service.d/override.conf << 'DROPIN'
[Service]
Environment=HOME=/var/lib/caddy
DROPIN
        systemctl daemon-reload
    fi

    # OpenRC 服务（Alpine）
    if has_cmd rc-service && [[ ! -f /etc/init.d/caddy ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.openrc" \
            -o /etc/init.d/caddy 2>/dev/null || true
        chmod +x /etc/init.d/caddy 2>/dev/null || true
    fi
}
