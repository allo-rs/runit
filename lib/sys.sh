#!/usr/bin/env bash
# 系统检测：发行版、架构、包管理器

# 检测 OS 类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="macos"
        OS_NAME="macOS"
        OS_VERSION="$(sw_vers -productVersion)"
    else
        die "不支持的操作系统"
    fi
    export OS_ID OS_NAME OS_VERSION
}

# 检测 CPU 架构
detect_arch() {
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *)       ARCH="$(uname -m)" ;;
    esac
    export ARCH
}

# 检测包管理器并导出安装命令
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update -y"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
        PKG_INSTALL="apk add"
        PKG_UPDATE="apk update"
    elif command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
        PKG_INSTALL="brew install"
        PKG_UPDATE="brew update"
    else
        PKG_MANAGER="unknown"
        warn "未检测到支持的包管理器"
    fi
    export PKG_MANAGER PKG_INSTALL PKG_UPDATE
}

# 检测是否 root
require_root() {
    [[ "$EUID" -eq 0 ]] || die "此操作需要 root 权限，请使用 sudo 运行"
}

# 打印系统信息摘要
print_sysinfo() {
    detect_os
    detect_arch
    detect_pkg_manager
    echo -e "  系统: ${BOLD}${OS_NAME} ${OS_VERSION}${NC}  架构: ${BOLD}${ARCH}${NC}  包管理器: ${BOLD}${PKG_MANAGER}${NC}"
}

# 安装依赖包（跨发行版）
pkg_install() {
    detect_pkg_manager
    [[ "$PKG_MANAGER" == "unknown" ]] && die "无法安装依赖：未找到包管理器"
    info "安装: $*"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        $PKG_UPDATE &>/dev/null
    fi
    $PKG_INSTALL "$@"
}
