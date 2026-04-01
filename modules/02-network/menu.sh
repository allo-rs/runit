#!/usr/bin/env bash
# 模块：网络工具

MENU_TITLE="网络工具"
MENU_ITEMS=(
    "IP 地址查询"
    "网络连通性测试"
    "端口检测"
    "DNS 查询"
    "网速测试 (speedtest)"
    "路由追踪"
)

menu_network() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_ipinfo ;;
            2) cmd_ping ;;
            3) cmd_portcheck ;;
            4) cmd_dns ;;
            5) cmd_speedtest ;;
            6) cmd_traceroute ;;
        esac
        press_any_key
    done
}

cmd_ipinfo() {
    title "IP 信息"
    info "获取本机公网 IP 信息..."
    local data
    data=$(curl -fsSL --max-time 5 https://ipinfo.io 2>/dev/null)
    if [[ -n "$data" ]]; then
        echo "$data" | grep -E '"ip"|"city"|"region"|"country"|"org"' | \
            sed 's/[",]//g; s/^  /  /'
    else
        warn "无法获取 IP 信息，检查网络连接"
    fi
}

cmd_ping() {
    title "连通性测试"
    local hosts=("1.1.1.1" "8.8.8.8" "baidu.com" "google.com")
    for host in "${hosts[@]}"; do
        local result
        if ping -c1 -W2 "$host" &>/dev/null; then
            local ms
            ms=$(ping -c1 -W2 "$host" 2>/dev/null | grep 'time=' | grep -oP 'time=\K[\d.]+')
            success "${host} (${ms}ms)"
        else
            error "${host} 不可达"
        fi
    done
}

cmd_portcheck() {
    title "端口检测"
    read -rp "$(echo -e "  输入 IP 或域名: ")" target
    read -rp "$(echo -e "  输入端口: ")" port
    [[ -z "$target" || -z "$port" ]] && { warn "参数不能为空"; return; }
    if has_cmd nc; then
        nc -zw3 "$target" "$port" 2>/dev/null && success "端口 ${port} 开放" || error "端口 ${port} 关闭"
    else
        timeout 3 bash -c ">/dev/tcp/${target}/${port}" 2>/dev/null && \
            success "端口 ${port} 开放" || error "端口 ${port} 关闭"
    fi
}

cmd_dns() {
    title "DNS 查询"
    read -rp "$(echo -e "  输入域名: ")" domain
    [[ -z "$domain" ]] && return
    if has_cmd dig; then
        dig +short "$domain" A
        dig +short "$domain" AAAA
    else
        nslookup "$domain"
    fi
}

cmd_speedtest() {
    title "网速测试 (librespeed)"

    local bin="/usr/local/bin/librespeed-cli"

    # 已安装则直接运行
    if [[ -x "$bin" ]]; then
        "$bin"
        return
    fi

    info "未检测到 librespeed-cli，开始下载..."
    detect_arch

    local os_str="linux"
    [[ "$(uname)" == "Darwin" ]] && os_str="darwin"

    local bin_arch
    case "$ARCH" in
        amd64) bin_arch="amd64" ;;
        arm64) bin_arch="arm64" ;;
        armv7) bin_arch="armv7" ;;
        *)     die "不支持的架构：${ARCH}" ;;
    esac

    # 获取最新版本
    local version
    version=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest-cli/releases/latest \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"\(v[^"]*\)".*/\1/')
    [[ -z "$version" ]] && die "无法获取版本信息，请检查网络"

    local url="https://github.com/librespeed/speedtest-cli/releases/download/${version}/librespeed-cli_${version#v}_${os_str}_${bin_arch}.tar.gz"
    info "下载 librespeed-cli ${version}..."

    local tmp
    tmp=$(mktemp -d)
    if ! curl -fsSL "$url" -o "${tmp}/librespeed.tar.gz"; then
        rm -rf "$tmp"
        die "下载失败，请检查网络或手动安装"
    fi

    tar -xzf "${tmp}/librespeed.tar.gz" -C "$tmp"
    install -m 755 "${tmp}/librespeed-cli" "$bin" 2>/dev/null || \
        install -m 755 "${tmp}/librespeed-cli" "$HOME/.local/bin/librespeed-cli" 2>/dev/null || \
        { rm -rf "$tmp"; die "安装失败，请以 root 运行"; }
    rm -rf "$tmp"

    success "librespeed-cli 已安装至 ${bin}"
    echo
    "$bin"
}

cmd_traceroute() {
    title "路由追踪"
    read -rp "$(echo -e "  输入目标 IP 或域名 [默认 1.1.1.1]: ")" target
    target="${target:-1.1.1.1}"
    if has_cmd traceroute; then
        traceroute -m 20 "$target"
    elif has_cmd tracepath; then
        tracepath "$target"
    else
        warn "未找到 traceroute/tracepath"
    fi
}
