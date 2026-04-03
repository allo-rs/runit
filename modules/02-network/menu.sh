#!/usr/bin/env bash
# 模块：网络工具

MENU_TITLE="网络工具"
MENU_ITEMS=(
    "IP 地址查询"
    "网络连通性测试"
    "端口检测"
    "DNS 查询"
    "网速测试 (Cloudflare)"
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
        local result ms
        result=$(ping -c1 -W2 "$host" 2>/dev/null)
        if echo "$result" | grep -q 'time='; then
            ms=$(echo "$result" | grep -oP 'time=\K[\d.]+')
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
        dig +short +time=2 +tries=1 "$domain" A
        dig +short +time=2 +tries=1 "$domain" AAAA
    else
        nslookup "$domain"
    fi
}

cmd_speedtest() {
    title "网速测试 (Cloudflare)"

    # 使用 curl 计算速度（单位：bytes/s），转换为 Mbps
    _cf_speed_mbps() {
        local bytes_per_sec="$1"
        awk "BEGIN { printf \"%.2f\", $bytes_per_sec * 8 / 1000000 }"
    }

    # 下载测试：从 Cloudflare 拉取指定大小文件，取多轮平均，单次限时 8s
    _test_download() {
        local sizes=(5000000 10000000 20000000)  # 5MB / 10MB / 20MB
        local total=0 count=0

        info "测试下载速度..."
        for size in "${sizes[@]}"; do
            local speed
            speed=$(curl -fsSL -o /dev/null \
                --max-time 8 \
                -w "%{speed_download}" \
                "https://speed.cloudflare.com/__down?bytes=${size}" 2>/dev/null)
            [[ -z "$speed" || "$speed" == "0" ]] && continue
            total=$(awk "BEGIN { print $total + $speed }")
            (( count++ ))
        done

        if (( count == 0 )); then
            echo "N/A"
        else
            local avg
            avg=$(awk "BEGIN { print $total / $count }")
            _cf_speed_mbps "$avg"
        fi
    }

    # 上传测试：向 Cloudflare 上传 /dev/zero 数据，取多轮平均，单次限时 8s
    _test_upload() {
        local sizes=(2000000 5000000 10000000)  # 2MB / 5MB / 10MB
        local total=0 count=0

        info "测试上传速度..."
        for size in "${sizes[@]}"; do
            local speed
            speed=$(dd if=/dev/zero bs=1024 count=$(( size / 1024 )) 2>/dev/null \
                | curl -fsSL -X POST \
                    -H "Content-Type: application/octet-stream" \
                    --max-time 8 \
                    --data-binary @- \
                    -o /dev/null \
                    -w "%{speed_upload}" \
                    "https://speed.cloudflare.com/__up" 2>/dev/null)
            [[ -z "$speed" || "$speed" == "0" ]] && continue
            total=$(awk "BEGIN { print $total + $speed }")
            (( count++ ))
        done

        if (( count == 0 )); then
            echo "N/A"
        else
            local avg
            avg=$(awk "BEGIN { print $total / $count }")
            _cf_speed_mbps "$avg"
        fi
    }

    # 测延迟
    info "测试延迟..."
    local latency
    latency=$(curl -fsSL -o /dev/null \
        -w "%{time_connect}" \
        "https://speed.cloudflare.com/__down?bytes=0" 2>/dev/null)
    local latency_ms
    latency_ms=$(awk "BEGIN { printf \"%.1f\", $latency * 1000 }")

    local dl ul
    dl=$(_test_download)
    ul=$(_test_upload)

    echo
    echo "  ┌─────────────────────────────────┐"
    printf "  │  延迟（Latency）     %8s ms  │\n" "$latency_ms"
    printf "  │  下载（Download）    %8s Mbps│\n" "$dl"
    printf "  │  上传（Upload）      %8s Mbps│\n" "$ul"
    echo "  │  测试节点：Cloudflare CDN       │"
    echo "  └─────────────────────────────────┘"
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
