#!/usr/bin/env bash
# runit 安装脚本
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/user/runit/main/install.sh)

set -euo pipefail

REPO="allo-rs/runit"
INSTALL_DIR="/usr/local/lib/runit"
BIN_PATH="/usr/local/bin/runit"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"

# 颜色
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "${CYAN}[·]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
die()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# 检测 root
[[ "$EUID" -eq 0 ]] || die "请使用 root 权限运行: sudo bash install.sh"

# 检测 curl
command -v curl &>/dev/null || die "需要安装 curl"

echo -e "\n${BOLD}安装 runit...${NC}\n"

# 创建目录
info "创建目录: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/lib"
mkdir -p "${INSTALL_DIR}/modules"/{01-system,02-network,03-security,04-apps,05-optimize}

# 下载文件列表
FILES=(
    "runit.sh"
    "lib/ui.sh"
    "lib/sys.sh"
    "lib/utils.sh"
    "modules/01-system/menu.sh"
    "modules/02-network/menu.sh"
)

for f in "${FILES[@]}"; do
    info "下载 ${f}..."
    curl -fsSL "${RAW_BASE}/${f}" -o "${INSTALL_DIR}/${f}"
done

# 设置可执行权限
chmod +x "${INSTALL_DIR}/runit.sh"

# 创建全局命令
cat > "${BIN_PATH}" << EOF
#!/usr/bin/env bash
exec bash "${INSTALL_DIR}/runit.sh" "\$@"
EOF
chmod +x "${BIN_PATH}"

echo
ok "安装完成！"
echo -e "\n  运行 ${BOLD}runit${NC} 启动工具集"
echo -e "  运行 ${BOLD}runit --help${NC} 查看帮助\n"
