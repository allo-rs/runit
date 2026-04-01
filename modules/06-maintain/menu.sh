#!/usr/bin/env bash
# 模块：维护工具

MENU_TITLE="维护工具"
MENU_ITEMS=(
    "清理 runit 运行缓存"
)

menu_maintain() {
    while true; do
        render_menu "$MENU_TITLE" "${MENU_ITEMS[@]}"
        local choice
        choice=$(read_choice "${#MENU_ITEMS[@]}")
        case "$choice" in
            0) return ;;
            1) cmd_cleanup ;;
        esac
        press_any_key
    done
}

cmd_cleanup() {
    title "清理 runit 运行缓存"

    local found=0

    # ── /tmp 残留目录（mktemp 创建，中断后可能残留）──────────
    local tmp_dirs
    tmp_dirs=$(find /tmp -maxdepth 1 -type d -name 'tmp.*' -user root 2>/dev/null)
    if [[ -n "$tmp_dirs" ]]; then
        info "发现 /tmp 残留目录："
        echo "$tmp_dirs" | sed 's/^/  /'
        found=1
    fi

    # ── librespeed-cli 二进制 ────────────────────────────────
    local librespeed_paths=("/usr/local/bin/librespeed-cli" "$HOME/.local/bin/librespeed-cli")
    local found_librespeed=()
    for p in "${librespeed_paths[@]}"; do
        [[ -f "$p" ]] && found_librespeed+=("$p")
    done
    if [[ ${#found_librespeed[@]} -gt 0 ]]; then
        info "发现 librespeed-cli 二进制："
        printf '  %s\n' "${found_librespeed[@]}"
        found=1
    fi

    # ── SSH 配置备份文件 ─────────────────────────────────────
    local sshd_backups
    sshd_backups=$(find /etc/ssh -maxdepth 1 -name 'sshd_config.bak.*' 2>/dev/null)
    if [[ -n "$sshd_backups" ]]; then
        info "发现 SSH 配置备份："
        echo "$sshd_backups" | sed 's/^/  /'
        found=1
    fi

    # ── 无内容 ───────────────────────────────────────────────
    if [[ "$found" -eq 0 ]]; then
        success "没有发现需要清理的内容"
        return
    fi

    echo
    confirm "确认删除以上所有内容？" || { warn "已取消"; return; }

    local cleaned=0

    # 删除 /tmp 残留
    if [[ -n "$tmp_dirs" ]]; then
        echo "$tmp_dirs" | xargs rm -rf
        success "已清理 /tmp 残留目录"
        ((cleaned++))
    fi

    # 删除 librespeed-cli
    for p in "${found_librespeed[@]}"; do
        rm -f "$p"
        success "已删除 ${p}"
        ((cleaned++))
    done

    # 删除 SSH 备份（保留最新一份）
    if [[ -n "$sshd_backups" ]]; then
        local latest
        latest=$(echo "$sshd_backups" | sort | tail -1)
        echo "$sshd_backups" | grep -v "^${latest}$" | xargs rm -f 2>/dev/null
        local removed_count
        removed_count=$(echo "$sshd_backups" | wc -l)
        if [[ "$removed_count" -gt 1 ]]; then
            success "已清理旧 SSH 备份，保留最新：$(basename "$latest")"
        else
            success "仅有一份 SSH 备份，已保留：$(basename "$latest")"
        fi
        ((cleaned++))
    fi

    echo
    divider
    success "清理完成，共处理 ${cleaned} 项"
    divider
}
