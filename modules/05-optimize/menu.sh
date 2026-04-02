#!/usr/bin/env bash
# 模块：系统优化

MENU_TITLE="系统优化"
MENU_ITEMS=(
    "BBR 状态检测"
    "启用 BBR 加速"
)

menu_optimize() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_check_bbr ;;
            2) cmd_enable_bbr ;;
        esac
        press_any_key
    done
}

# ── BBR 状态检测 ─────────────────────────────────────────────

cmd_check_bbr() {
    title "BBR 状态检测"

    # 内核版本
    local kernel
    kernel=$(uname -r)
    info "内核版本：${kernel}"

    # 解析主版本号，检查是否 >= 4.9
    local major minor
    major=$(echo "$kernel" | cut -d. -f1)
    minor=$(echo "$kernel" | cut -d. -f2)
    if [[ "$major" -gt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -ge 9 ]]; }; then
        echo -e "  ${GREEN}✔${NC} 内核版本满足要求（>= 4.9）"
    else
        echo -e "  ${RED}✘${NC} 内核版本过低，BBR 需要 4.9 或更高版本"
        return
    fi

    echo

    # tcp_bbr 模块是否已加载
    if lsmod 2>/dev/null | grep -q "^tcp_bbr"; then
        echo -e "  ${GREEN}✔${NC} tcp_bbr 模块已加载"
    else
        echo -e "  ${YELLOW}!${NC} tcp_bbr 模块未加载"
    fi

    # 当前拥塞控制算法
    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    if [[ "$cc" == "bbr" ]]; then
        echo -e "  ${GREEN}✔${NC} 拥塞控制算法：${BOLD}${cc}${NC}"
    else
        echo -e "  ${YELLOW}!${NC} 拥塞控制算法：${cc}（非 BBR）"
    fi

    # 队列调度算法
    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    if [[ "$qdisc" == "fq" ]]; then
        echo -e "  ${GREEN}✔${NC} 队列调度算法：${BOLD}${qdisc}${NC}"
    else
        echo -e "  ${YELLOW}!${NC} 队列调度算法：${qdisc}（推荐 fq）"
    fi

    echo

    # 综合判断
    if [[ "$cc" == "bbr" ]] && [[ "$qdisc" == "fq" ]]; then
        success "BBR 已完整启用！"
    elif [[ "$cc" == "bbr" ]]; then
        warn "BBR 已启用，但队列调度未设置为 fq，效果可能不完整"
    else
        warn "BBR 未启用，可选择「启用 BBR 加速」"
    fi
}

# ── 启用 BBR ─────────────────────────────────────────────────

cmd_enable_bbr() {
    require_root
    title "启用 BBR 加速"

    # 内核版本检查
    local kernel major minor
    kernel=$(uname -r)
    major=$(echo "$kernel" | cut -d. -f1)
    minor=$(echo "$kernel" | cut -d. -f2)
    if ! { [[ "$major" -gt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -ge 9 ]]; }; }; then
        error "内核版本 ${kernel} 不支持 BBR，需要 >= 4.9"
        return
    fi

    # 已完整启用则提示
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
    if [[ "$cc" == "bbr" ]] && [[ "$qdisc" == "fq" ]]; then
        success "BBR 已完整启用，无需重复操作"
        return
    fi

    confirm "即将修改内核网络参数，是否继续？" || return

    # 加载 tcp_bbr 模块
    info "加载 tcp_bbr 模块..."
    if ! modprobe tcp_bbr 2>/dev/null; then
        # 部分内核已内置，忽略加载失败
        warn "modprobe tcp_bbr 失败（模块可能已内置，继续...）"
    fi

    # 持久化模块加载
    local modules_conf="/etc/modules-load.d/bbr.conf"
    if [[ ! -f "$modules_conf" ]]; then
        echo "tcp_bbr" > "$modules_conf"
        info "已创建模块自动加载配置：${modules_conf}"
    fi

    # 写入 sysctl 配置（独立文件，不污染主配置）
    local sysctl_conf="/etc/sysctl.d/99-bbr.conf"
    info "写入 sysctl 配置：${sysctl_conf}"
    cat > "$sysctl_conf" << 'EOF'
# BBR 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    # 立即生效
    info "应用配置..."
    if ! sysctl -p "$sysctl_conf" &>/dev/null; then
        error "sysctl 配置应用失败，请检查内核是否支持 BBR"
        rm -f "$sysctl_conf"
        return
    fi

    echo

    # 验证结果
    local new_cc new_qdisc
    new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    new_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo -e "  拥塞控制：${BOLD}${new_cc}${NC}"
    echo -e "  队列调度：${BOLD}${new_qdisc}${NC}"
    echo

    if [[ "$new_cc" == "bbr" ]] && [[ "$new_qdisc" == "fq" ]]; then
        success "BBR 启用成功，重启后自动生效！"
    else
        warn "配置已写入，但当前生效状态异常，建议重启服务器后再次验证"
    fi
}
