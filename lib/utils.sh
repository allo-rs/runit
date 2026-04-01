#!/usr/bin/env bash
# 通用工具函数

# 检测命令是否存在
has_cmd() { command -v "$1" &>/dev/null; }

# 下载文件（自动选择 curl/wget）
download() {
    local url="$1" dest="$2"
    if has_cmd curl; then
        curl -fsSL "$url" -o "$dest"
    elif has_cmd wget; then
        wget -qO "$dest" "$url"
    else
        die "需要 curl 或 wget"
    fi
}

# 远程执行脚本（带提示）
run_remote() {
    local url="$1"
    local desc="${2:-远程脚本}"
    info "执行: ${desc}"
    info "来源: ${url}"
    confirm "确认执行此脚本？" || return 0
    bash <(curl -fsSL "$url")
}

# 检测端口是否占用
port_in_use() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port} " || \
    netstat -tlnp 2>/dev/null | grep -q ":${port} "
}

# 等待用户按任意键继续
press_any_key() {
    echo -e "\n${DIM}按任意键继续...${NC}"
    read -rn1
}

# 格式化文件大小
human_size() {
    local bytes="$1"
    if ((bytes < 1024)); then echo "${bytes}B"
    elif ((bytes < 1048576)); then echo "$((bytes/1024))KB"
    elif ((bytes < 1073741824)); then echo "$((bytes/1048576))MB"
    else echo "$((bytes/1073741824))GB"
    fi
}

# 备份文件（加时间戳后缀）
backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
}
