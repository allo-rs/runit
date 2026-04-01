#!/usr/bin/env bash
# 模块：系统信息

MENU_TITLE="系统信息"
MENU_ITEMS=(
    "查看系统概览"
    "CPU 详细信息"
    "内存使用情况"
    "磁盘使用情况"
    "网络接口信息"
    "系统负载与进程"
)

menu_system() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_overview ;;
            2) cmd_cpu ;;
            3) cmd_memory ;;
            4) cmd_disk ;;
            5) cmd_network ;;
            6) cmd_load ;;
        esac
        press_any_key
    done
}

cmd_overview() {
    title "系统概览"
    print_sysinfo
    echo
    echo -e "  主机名:   ${BOLD}$(hostname)${NC}"
    echo -e "  运行时间: ${BOLD}$(uptime -p 2>/dev/null || uptime)${NC}"
    echo -e "  内核版本: ${BOLD}$(uname -r)${NC}"
    echo -e "  当前时间: ${BOLD}$(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
}

cmd_cpu() {
    title "CPU 信息"
    if [[ -f /proc/cpuinfo ]]; then
        local model cores
        model=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        cores=$(nproc)
        echo -e "  型号: ${BOLD}${model}${NC}"
        echo -e "  核心: ${BOLD}${cores}${NC}"
        echo
        grep 'MHz\|cache' /proc/cpuinfo | head -4 | sed 's/^/  /'
    else
        sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "  无法获取 CPU 信息"
    fi
}

cmd_memory() {
    title "内存信息"
    free -h 2>/dev/null || vm_stat
}

cmd_disk() {
    title "磁盘使用"
    df -hT 2>/dev/null | grep -v tmpfs | grep -v udev || df -h
}

cmd_network() {
    title "网络接口"
    ip addr 2>/dev/null | grep -E 'inet|^[0-9]' || ifconfig
}

cmd_load() {
    title "系统负载"
    echo -e "  负载均值: ${BOLD}$(cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg)${NC}"
    echo
    echo "  Top 10 进程 (按 CPU):"
    ps aux --sort=-%cpu 2>/dev/null | head -11 | sed 's/^/  /' || \
    ps aux | sort -rk3 | head -11 | sed 's/^/  /'
}
