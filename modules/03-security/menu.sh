#!/usr/bin/env bash
# 模块：安全配置

MENU_TITLE="安全配置"
MENU_ITEMS=(
    "配置 SSH 公钥登录（关闭密码验证）"
)

menu_security() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_setup_pubkey ;;
        esac
        press_any_key
    done
}

cmd_setup_pubkey() {
    require_root

    title "配置 SSH 公钥登录"

    local sshd_config="/etc/ssh/sshd_config"
    [[ -f "$sshd_config" ]] || die "未找到 ${sshd_config}，请确认 SSH 已安装"

    # ── 1. 输入公钥 ────────────────────────────────────────────
    echo -e "  请粘贴你的 SSH 公钥（以 ssh-rsa / ssh-ed25519 等开头）："
    echo -e "  ${DIM}提示：本机执行 \`cat ~/.ssh/id_ed25519.pub\` 获取公钥${NC}\n"
    read -rp "  公钥: " pubkey

    # 简单格式校验
    if ! echo "$pubkey" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519) '; then
        die "公钥格式不正确，应以 ssh-rsa / ssh-ed25519 等开头"
    fi

    # ── 2. 写入 authorized_keys ────────────────────────────────
    local auth_keys="$HOME/.ssh/authorized_keys"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # 检查是否已存在相同公钥
    if [[ -f "$auth_keys" ]] && grep -qF "$pubkey" "$auth_keys"; then
        warn "该公钥已存在于 ${auth_keys}，跳过写入"
    else
        echo "$pubkey" >> "$auth_keys"
        chmod 600 "$auth_keys"
        success "公钥已写入 ${auth_keys}"
    fi

    # ── 3. 修改 sshd_config ────────────────────────────────────
    echo
    info "修改 ${sshd_config}..."
    backup_file "$sshd_config"
    success "已备份原配置: ${sshd_config}.bak.*"

    # 设置或替换配置项
    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?[[:space:]]*${key}[[:space:]]" "$sshd_config"; then
            # 存在（含注释行）→ 替换
            sed -i.tmp "s|^#\?[[:space:]]*${key}[[:space:]].*|${key} ${val}|" "$sshd_config"
        else
            # 不存在 → 追加
            echo "${key} ${val}" >> "$sshd_config"
        fi
        rm -f "${sshd_config}.tmp"
    }

    _sshd_set "PubkeyAuthentication"   "yes"
    _sshd_set "AuthorizedKeysFile"     ".ssh/authorized_keys"
    _sshd_set "PasswordAuthentication" "no"
    _sshd_set "ChallengeResponseAuthentication" "no"
    _sshd_set "UsePAM"                 "yes"

    success "sshd_config 已更新"

    # ── 4. 验证配置语法 ────────────────────────────────────────
    echo
    info "验证配置语法..."
    if sshd -t 2>/dev/null; then
        success "配置语法正确"
    else
        error "配置语法有误！正在还原备份..."
        local backup
        backup=$(ls -t "${sshd_config}.bak."* 2>/dev/null | head -1)
        if [[ -n "$backup" ]]; then
            cp "$backup" "$sshd_config"
            error "已还原备份: ${backup}"
        fi
        die "请手动检查 ${sshd_config}"
    fi

    # ── 5. 重启 sshd ───────────────────────────────────────────
    echo
    warn "即将重启 SSH 服务，确保当前会话 公钥已正确配置，否则可能被锁出！"
    confirm "确认重启 sshd？" || { warn "已取消，请手动执行: systemctl restart sshd"; return; }

    if systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null; then
        success "SSH 服务已重启"
    else
        warn "自动重启失败，请手动执行: systemctl restart sshd"
    fi

    # ── 6. 汇总 ────────────────────────────────────────────────
    echo
    divider
    success "配置完成！当前状态："
    echo -e "  ${GREEN}✓${NC} 公钥登录：已开启"
    echo -e "  ${GREEN}✓${NC} 密码登录：已关闭"
    echo -e "  ${YELLOW}!${NC} 请用新终端测试公钥登录后，再关闭此会话"
    divider
}
