#!/usr/bin/env bash
# 模块：应用安装

MENU_TITLE="应用安装"
MENU_ITEMS=(
    "安装 Docker"
    "安装 Caddy"
    "安装 PostgreSQL (Docker Compose)"
    "修改 PostgreSQL 密码"
    "安装 ddns-go"
    "管理 ddns-go"
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
            4) cmd_change_postgres_password ;;
            5) cmd_install_ddns_go ;;
            6) menu_ddns_go_manage ;;
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

    # ── 创建 caddy 用户与目录 ──────────────────────────────────
    id -u caddy &>/dev/null || useradd -r -s /sbin/nologin caddy
    mkdir -p /etc/caddy /var/log/caddy /var/lib/caddy
    chown caddy:caddy /etc/caddy /var/log/caddy /var/lib/caddy
    chmod 750 /etc/caddy

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

    # ── 写入默认 Caddyfile（必须在服务启动前存在，否则 ExecStart 直接退出）──
    local caddyfile="/etc/caddy/Caddyfile"
    if [[ ! -s "$caddyfile" ]]; then
        cat > "$caddyfile" << 'EOF'
# 文档：https://caddyserver.com/docs/caddyfile

:80 {
    respond "Caddy is running!"
}
EOF
        info "已创建默认配置：${caddyfile}"
    fi
    chown caddy:caddy "$caddyfile"
    chmod 644 "$caddyfile"

    if ! caddy validate --config "$caddyfile" 2>/dev/null; then
        die "Caddyfile 语法校验未通过，已中止启动，请检查：${caddyfile}"
    fi

    # ── 启动并开机自启 ─────────────────────────────────────────
    if has_cmd rc-service; then
        # Alpine / OpenRC：caddy.env 是主配置；/etc/conf.d/caddy 供 OpenRC init 脚本注入环境变量
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
        if systemctl is-active --quiet caddy; then
            systemctl restart caddy
        else
            systemctl enable --now caddy
        fi
    fi

    echo
    success "Caddy 安装完成"
    caddy version
    echo
    info "配置文件：${caddyfile}"
    [[ -n "$cf_token" ]] && info "Token 文件：${env_file}"
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

    local pg_default_pass
    pg_default_pass=$(tr -dc 'A-Za-z0-9@%' </dev/urandom | head -c 20 || true)
    read -rsp "$(echo -e "${CYAN}数据库密码 [回车自动生成]: ${NC}")"      pg_password
    echo
    pg_password="${pg_password:-$pg_default_pass}"

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

        # 数据目录存在时询问是否清除
        # PostgreSQL 仅在数据目录为空时才读取 POSTGRES_PASSWORD 初始化
        # 若保留旧数据，新密码不会生效
        if [[ -d "$pg_data_dir" ]] && [[ -n "$(ls -A "$pg_data_dir" 2>/dev/null)" ]]; then
            warn "检测到旧数据目录：${pg_data_dir}"
            warn "保留旧数据则新密码不会生效（PostgreSQL 仅在首次初始化时读取密码）"
            if confirm "是否清除旧数据（将删除所有数据库内容）？"; then
                rm -rf "${pg_data_dir:?}"/*
                info "旧数据已清除，将以新密码重新初始化"
            else
                info "保留旧数据，新密码不会生效，连接时请使用旧密码"
            fi
        fi
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
      POSTGRES_PASSWORD: '${pg_password}'
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
        i=$((i + 1))
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
    info "连接 URL："
    echo -e "  postgresql://${pg_user}:${pg_password}@127.0.0.1:${pg_port}/${pg_db}?sslmode=disable"
    echo
    info "常用命令："
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml ps"
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml logs -f"
    echo -e "  docker compose -f ${compose_dir}/docker-compose.yml down"
    echo -e "  psql -h 127.0.0.1 -p ${pg_port} -U ${pg_user} -d ${pg_db}"
}

cmd_change_postgres_password() {
    require_root
    title "修改 PostgreSQL 密码"

    local compose_dir pg_user pg_db new_password
    read -rp "$(echo -e "${CYAN}Compose 文件目录 [/opt/postgres]: ${NC}")" compose_dir
    compose_dir="${compose_dir:-/opt/postgres}"

    if [[ ! -f "${compose_dir}/docker-compose.yml" ]]; then
        error "未找到配置文件：${compose_dir}/docker-compose.yml"
        return 1
    fi

    # 从现有 compose 文件读取用户名和数据库名
    pg_user=$(grep 'POSTGRES_USER' "${compose_dir}/docker-compose.yml" | awk -F': ' '{print $2}' | tr -d ' ')
    pg_db=$(grep 'POSTGRES_DB' "${compose_dir}/docker-compose.yml" | awk -F': ' '{print $2}' | tr -d ' ')
    pg_user="${pg_user:-postgres}"
    pg_db="${pg_db:-postgres}"

    local default_pass
    default_pass=$(tr -dc 'A-Za-z0-9@#$%' </dev/urandom | head -c 16 || true)
    read -rsp "$(echo -e "${CYAN}新密码 [回车自动生成]: ${NC}")" new_password
    echo
    new_password="${new_password:-$default_pass}"

    # 通过 psql 在运行中的容器内修改密码
    if ! docker compose -f "${compose_dir}/docker-compose.yml" exec -T postgres \
            psql -U "$pg_user" -d "$pg_db" -c "ALTER USER ${pg_user} PASSWORD '${new_password}';" &>/dev/null; then
        error "密码修改失败，请确认容器正在运行（docker compose ps）"
        return 1
    fi

    # 同步更新 docker-compose.yml 中的密码，保持文件与实际一致
    sed -i "s|POSTGRES_PASSWORD:.*|POSTGRES_PASSWORD: '${new_password}'|" "${compose_dir}/docker-compose.yml"

    success "密码已修改"
    echo -e "  用户：${pg_user}"
    echo -e "  新密码：${new_password}"
}

cmd_install_ddns_go() {
    require_root
    title "安装 ddns-go (Cloudflare)"

    if has_cmd ddns-go; then
        local ver
        ver=$(ddns-go -v 2>/dev/null | head -1 || true)
        warn "ddns-go 已安装：${ver}"
        confirm "是否重新安装/升级？" || return
        ddns-go -s stop 2>/dev/null || true
        ddns-go -s uninstall 2>/dev/null || true
    fi

    # ── 收集配置 ──────────────────────────────────────────────
    local cf_token ddns_interval
    read -rsp "$(echo -e "${CYAN}Cloudflare API Token: ${NC}")" cf_token
    echo
    [[ -n "$cf_token" ]] || { error "Token 不能为空"; return 1; }

    echo
    info "IPv4 域名（每行一个，留空结束）："
    local domains_v4=()
    while true; do
        read -rp "  域名: " _d
        [[ -z "$_d" ]] && break
        domains_v4+=("$_d")
    done
    [[ ${#domains_v4[@]} -gt 0 ]] || { error "至少需要一个域名"; return 1; }

    local enable_ipv6=false domains_v6=()
    if confirm "同时更新 IPv6 (AAAA) 记录？"; then
        enable_ipv6=true
        info "IPv6 域名（留空则与 IPv4 相同）："
        while true; do
            read -rp "  域名: " _d
            [[ -z "$_d" ]] && break
            domains_v6+=("$_d")
        done
        [[ ${#domains_v6[@]} -eq 0 ]] && domains_v6=("${domains_v4[@]}")
    fi

    read -rp "$(echo -e "${CYAN}IP 检测间隔（秒）[300]: ${NC}")" ddns_interval
    ddns_interval="${ddns_interval:-300}"

    # ── 安装二进制 ────────────────────────────────────────────
    _ddns_go_install_binary

    # ── 写入配置文件 ──────────────────────────────────────────
    local config_file="/root/.ddns_go_config.yaml"
    _ddns_go_write_config "$cf_token" "$enable_ipv6" "$ddns_interval" \
        "${domains_v4[*]}" "${domains_v6[*]}" > "$config_file"
    chmod 600 "$config_file"

    # ── 安装服务（-noweb 禁用 Web UI） ────────────────────────
    ddns-go -s install -f "${ddns_interval}" -noweb
    ddns-go -s start

    echo
    success "ddns-go 安装完成"
    ddns-go -v 2>/dev/null | head -1 || true
    echo
    info "配置文件：${config_file}"
    info "IPv4 域名："
    for _d in "${domains_v4[@]}"; do echo -e "  ${_d}"; done
    if [[ "$enable_ipv6" == "true" ]]; then
        info "IPv6 域名："
        for _d in "${domains_v6[@]}"; do echo -e "  ${_d}"; done
    fi
    echo
    info "常用命令："
    echo -e "  ddns-go -s start      # 启动"
    echo -e "  ddns-go -s stop       # 停止"
    echo -e "  ddns-go -s restart    # 重启"
    echo -e "  ddns-go -s uninstall  # 卸载服务"
}

_ddns_go_write_config() {
    local token="$1" enable_ipv6="$2" interval="$3"
    local -a v4_domains=() v6_domains=()
    IFS=' ' read -ra v4_domains <<< "$4"
    IFS=' ' read -ra v6_domains <<< "$5"

    # 构建域名缩进列表
    local v4_list="" v6_list=""
    for d in "${v4_domains[@]}"; do v4_list+="    - ${d}"$'\n'; done
    for d in "${v6_domains[@]}"; do v6_list+="    - ${d}"$'\n'; done

    local ipv6_enable="false"
    [[ "$enable_ipv6" == "true" ]] && ipv6_enable="true"

    cat << EOF
dnsconf:
- name: cloudflare
  ipv4:
    enable: true
    gettype: url
    url: https://myip.ipip.net
    domains:
${v4_list}  ipv6:
    enable: ${ipv6_enable}
    gettype: url
    url: https://6.ipw.cn
    domains:
${v6_list}  dns:
    name: cloudflare
    id: ""
    secret: ${token}
  ttl: ""
username: ""
password: ""
notallowwanaccess: true
lang: zh
EOF
}

_ddns_go_install_binary() {
    detect_arch
    local file_arch
    case "$ARCH" in
        amd64) file_arch="x86_64" ;;
        arm64) file_arch="arm64" ;;
        armv7) file_arch="armv7" ;;
        *)     die "不支持的架构：${ARCH}" ;;
    esac

    info "获取最新版本..."
    local version
    version=$(curl -sL "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    [[ -n "$version" ]] || die "获取版本号失败，请检查网络"
    info "最新版本：v${version}"

    local filename="ddns-go_${version}_linux_${file_arch}.tar.gz"
    local url="https://github.com/jeessy2/ddns-go/releases/download/v${version}/${filename}"
    info "下载：${url}"

    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "${tmp}/${filename}" || die "下载失败，请检查网络"
    tar -xzf "${tmp}/${filename}" -C "$tmp" || die "解压失败"
    [[ -f "${tmp}/ddns-go" ]] || die "未找到 ddns-go 可执行文件"
    chmod +x "${tmp}/ddns-go"
    "${tmp}/ddns-go" -v &>/dev/null || die "下载的二进制无法执行，请重试"
    install -m 755 "${tmp}/ddns-go" /usr/bin/ddns-go
    rm -rf "$tmp"
}

# ── ddns-go 管理子菜单 ───────────────────────────────────────

_DDNS_GO_CONFIG="/root/.ddns_go_config.yaml"

_DDNS_GO_MANAGE_ITEMS=(
    "查看当前配置"
    "修改配置"
    "查看服务状态"
    "重启服务"
)

menu_ddns_go_manage() {
    while true; do
        render_menu "管理 ddns-go" "${_DDNS_GO_MANAGE_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#_DDNS_GO_MANAGE_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_show_ddns_go_config ;;
            2) cmd_edit_ddns_go_config ;;
            3) cmd_status_ddns_go ;;
            4) cmd_restart_ddns_go ;;
        esac
        press_any_key
    done
}

cmd_show_ddns_go_config() {
    title "ddns-go 当前配置"

    [[ -f "$_DDNS_GO_CONFIG" ]] || { error "配置文件不存在：${_DDNS_GO_CONFIG}"; return 1; }

    # 解析并展示，Token 脱敏
    local token domains_v4 domains_v6 interval

    token=$(grep '^\s*secret:' "$_DDNS_GO_CONFIG" | head -1 | sed 's/.*secret: *//')
    local token_masked="${token:0:6}****${token: -4}"

    echo
    info "配置文件：${_DDNS_GO_CONFIG}"
    echo
    info "DNS 服务商：Cloudflare"
    echo -e "  API Token：${token_masked}"
    echo

    info "IPv4 域名："
    awk '/ipv4:/,/ipv6:/' "$_DDNS_GO_CONFIG" | grep '^\s*- ' | sed 's/.*- /  /'

    local ipv6_enable
    ipv6_enable=$(awk '/ipv6:/,/dns:/' "$_DDNS_GO_CONFIG" | grep 'enable:' | head -1 | awk '{print $2}')
    if [[ "$ipv6_enable" == "true" ]]; then
        echo
        info "IPv6 域名："
        awk '/ipv6:/,/dns:/' "$_DDNS_GO_CONFIG" | grep '^\s*- ' | sed 's/.*- /  /'
    fi

    echo
    local status="未运行"
    if has_cmd systemctl && systemctl is-active --quiet ddns-go 2>/dev/null; then
        status="${GREEN}运行中${NC}"
    elif has_cmd rc-service && rc-service ddns-go status 2>/dev/null | grep -q started; then
        status="${GREEN}运行中${NC}"
    fi
    echo -e "  服务状态：${status}"
}

cmd_edit_ddns_go_config() {
    require_root
    title "修改 ddns-go 配置"

    [[ -f "$_DDNS_GO_CONFIG" ]] || { error "配置文件不存在，请先安装 ddns-go"; return 1; }

    # 读取旧值作为默认值
    local old_token old_interval
    old_token=$(grep '^\s*secret:' "$_DDNS_GO_CONFIG" | head -1 | sed 's/.*secret: *//')
    old_interval=""

    echo
    local cf_token
    read -rsp "$(echo -e "${CYAN}Cloudflare API Token [回车保留原值]: ${NC}")" cf_token
    echo
    cf_token="${cf_token:-$old_token}"

    echo
    info "IPv4 域名（每行一个，留空结束）："
    local domains_v4=()
    while true; do
        read -rp "  域名: " _d
        [[ -z "$_d" ]] && break
        domains_v4+=("$_d")
    done
    [[ ${#domains_v4[@]} -gt 0 ]] || { error "至少需要一个域名"; return 1; }

    local enable_ipv6=false domains_v6=()
    if confirm "同时更新 IPv6 (AAAA) 记录？"; then
        enable_ipv6=true
        info "IPv6 域名（留空则与 IPv4 相同）："
        while true; do
            read -rp "  域名: " _d
            [[ -z "$_d" ]] && break
            domains_v6+=("$_d")
        done
        [[ ${#domains_v6[@]} -eq 0 ]] && domains_v6=("${domains_v4[@]}")
    fi

    local ddns_interval
    read -rp "$(echo -e "${CYAN}IP 检测间隔（秒）[300]: ${NC}")" ddns_interval
    ddns_interval="${ddns_interval:-300}"

    _ddns_go_write_config "$cf_token" "$enable_ipv6" "$ddns_interval" \
        "${domains_v4[*]}" "${domains_v6[*]}" > "$_DDNS_GO_CONFIG"
    chmod 600 "$_DDNS_GO_CONFIG"

    cmd_restart_ddns_go
    success "配置已更新"
}

cmd_status_ddns_go() {
    title "ddns-go 服务状态"
    if has_cmd systemctl; then
        systemctl status ddns-go --no-pager 2>/dev/null || warn "服务未找到或未运行"
    elif has_cmd rc-service; then
        rc-service ddns-go status 2>/dev/null || warn "服务未找到或未运行"
    else
        error "无法检测服务状态（不支持的 init 系统）"
    fi
}

cmd_restart_ddns_go() {
    require_root
    info "重启 ddns-go 服务..."
    if has_cmd systemctl; then
        systemctl restart ddns-go && success "重启成功" || error "重启失败"
    elif has_cmd rc-service; then
        rc-service ddns-go restart && success "重启成功" || error "重启失败"
    else
        ddns-go -s stop 2>/dev/null || true
        ddns-go -s start && success "重启成功" || error "重启失败"
    fi
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
    # 验证下载文件是合法的 ELF 可执行文件（读取前4字节 magic：7f 45 4c 46）
    [[ "$(od -A n -t x1 -N 4 "${tmp}/caddy" | tr -d ' \n')" == "7f454c46" ]] \
        || die "下载文件不是有效的 ELF 可执行文件，请重试"
    chmod +x "${tmp}/caddy"
    "${tmp}/caddy" version &>/dev/null       || die "下载的 caddy 二进制无法执行，请重试"
    install -m 755 "${tmp}/caddy" /usr/bin/caddy
    rm -rf "$tmp"

    # 部署 systemd 服务（官方 caddy.service 已含 EnvironmentFile=-/etc/caddy/caddy.env）
    if has_cmd systemctl && [[ ! -f /etc/systemd/system/caddy.service ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.service" \
            -o /etc/systemd/system/caddy.service \
            || die "下载 caddy.service 失败，请检查网络"
        # 官方 service 未设置 HOME，caddy 无法写入配置自动保存目录
        mkdir -p /etc/systemd/system/caddy.service.d
        cat > /etc/systemd/system/caddy.service.d/override.conf << 'DROPIN'
[Service]
Environment=HOME=/var/lib/caddy
DROPIN
    fi

    # OpenRC 服务（Alpine）
    if has_cmd rc-service && [[ ! -f /etc/init.d/caddy ]]; then
        curl -fsSL "https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.openrc" \
            -o /etc/init.d/caddy 2>/dev/null || true
        chmod +x /etc/init.d/caddy 2>/dev/null || true
    fi
}
