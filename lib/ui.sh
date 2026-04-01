#!/usr/bin/env bash
# UI 工具：颜色、打印、菜单渲染

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # 重置

# 基础输出
info()    { echo -e "${CYAN}[·]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# 标题行
title() {
    local text="$1"
    local width=50
    local line=$(printf '─%.0s' $(seq 1 $width))
    echo -e "\n${BOLD}${BLUE}┌${line}┐${NC}"
    printf "${BOLD}${BLUE}│${NC}  %-$((width - 2))s${BOLD}${BLUE}│${NC}\n" "$text"
    echo -e "${BOLD}${BLUE}└${line}┘${NC}\n"
}

# 分隔线
divider() {
    echo -e "${DIM}$(printf '─%.0s' $(seq 1 50))${NC}"
}

# 确认提示 (默认 N)
confirm() {
    local msg="${1:-确认执行？}"
    read -rp "$(echo -e "${YELLOW}${msg} [y/N]${NC} ")" ans
    [[ "${ans,,}" == "y" ]]
}

# 显示 LOGO
show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
  ██████╗ ██╗   ██╗███╗   ██╗██╗████████╗
  ██╔══██╗██║   ██║████╗  ██║██║╚══██╔══╝
  ██████╔╝██║   ██║██╔██╗ ██║██║   ██║
  ██╔══██╗██║   ██║██║╚██╗██║██║   ██║
  ██║  ██║╚██████╔╝██║ ╚████║██║   ██║
  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝
EOF
    echo -e "${NC}${DIM}  服务器一键脚本工具集 | github.com/allo-rs/runit${NC}"
    divider
}

# 渲染菜单
# 用法: render_menu "标题" "选项1" "选项2" ...
render_menu() {
    local menu_title="$1"; shift
    local options=("$@")
    echo -e "\n${BOLD}  ${menu_title}${NC}\n"
    local i=1
    for opt in "${options[@]}"; do
        printf "  ${CYAN}%2d)${NC} %s\n" "$i" "$opt"
        ((i++))
    done
    echo -e "  ${DIM} 0) 返回上级 / 退出${NC}"
    divider
}

# 读取用户选择
read_choice() {
    local max="$1"
    local choice
    while true; do
        read -rp "$(echo -e "${BOLD}请选择 [0-${max}]: ${NC}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice <= max)); then
            echo "$choice"
            return
        fi
        warn "无效输入，请输入 0-${max} 之间的数字"
    done
}
