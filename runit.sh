#!/usr/bin/env bash
# runit - 服务器一键脚本工具集
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/allo-rs/runit/main/runit.sh)

set -euo pipefail

# ── 路径初始化 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULES_DIR="${SCRIPT_DIR}/modules"

# 远程运行时动态下载 lib
REMOTE_BASE="https://raw.githubusercontent.com/allo-rs/runit/main"

# ── 加载公共库 ──────────────────────────────────────────────
_load_lib() {
    local lib="$1"
    local local_path="${LIB_DIR}/${lib}"
    if [[ -f "$local_path" ]]; then
        # shellcheck source=/dev/null
        source "$local_path"
    else
        # 远程模式：从 GitHub 下载
        source <(curl -fsSL "${REMOTE_BASE}/lib/${lib}" 2>/dev/null) || {
            echo "[ERROR] 无法加载库: ${lib}" >&2
            exit 1
        }
    fi
}

_load_lib "ui.sh"
_load_lib "sys.sh"
_load_lib "utils.sh"

# ── 加载模块 ────────────────────────────────────────────────
_load_module() {
    local mod_path="$1"
    local local_path="${MODULES_DIR}/${mod_path}/menu.sh"
    if [[ -f "$local_path" ]]; then
        # shellcheck source=/dev/null
        source "$local_path"
    else
        source <(curl -fsSL "${REMOTE_BASE}/modules/${mod_path}/menu.sh" 2>/dev/null)
    fi
}

# ── 主菜单 ──────────────────────────────────────────────────
MAIN_MENU_ITEMS=(
    "系统信息"
    "网络工具"
    "安全配置"
    "应用安装"
    "系统优化"
    "维护工具"
)

MAIN_MENU_MODULES=(
    "01-system"
    "02-network"
    "03-security"
    "04-apps"
    "05-optimize"
    "06-maintain"
)

MAIN_MENU_FUNCS=(
    "menu_system"
    "menu_network"
    "menu_security"
    "menu_apps"
    "menu_optimize"
    "menu_maintain"
)

main_menu() {
    while true; do
        clear
        show_banner
        detect_os 2>/dev/null || true
        detect_arch 2>/dev/null || true
        print_sysinfo
        echo
        render_menu "主菜单" "${MAIN_MENU_ITEMS[@]}"

        local choice
        choice=$(read_choice "${#MAIN_MENU_ITEMS[@]}")

        [[ "$choice" -eq 0 ]] && { echo -e "\n${DIM}再见！${NC}\n"; exit 0; }

        local idx=$((choice - 1))
        local mod="${MAIN_MENU_MODULES[$idx]}"
        local fn="${MAIN_MENU_FUNCS[$idx]}"

        # 加载模块（仅首次）
        if ! declare -f "$fn" &>/dev/null; then
            info "加载模块: ${mod}..."
            if ! _load_module "$mod"; then
                warn "模块 ${mod} 暂未实现"
                press_any_key
                continue
            fi
        fi

        clear
        "$fn"
    done
}

# ── 入口 ────────────────────────────────────────────────────
main() {
    # 支持命令行直接运行子模块: ./runit.sh network
    if [[ $# -gt 0 ]]; then
        case "$1" in
            system)  _load_module "01-system"; menu_system ;;
            network) _load_module "02-network"; menu_network ;;
            -v|--version) echo "runit v0.1.0"; exit 0 ;;
            -h|--help)
                echo "用法: $0 [system|network|security|apps|optimize]"
                exit 0
                ;;
            *) die "未知命令: $1，使用 --help 查看帮助" ;;
        esac
        return
    fi

    main_menu
}

main "$@"
