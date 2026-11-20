#!/usr/bin/env bash
# Verify a fcitx5 + Rime install. Run after logging out and back in.
# Exit 0 = healthy, 1 = at least one check failed.
set -uo pipefail

fail=0
check() {
    local name=$1
    shift
    if "$@"; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s\n' "$name"
        fail=1
    fi
}

fcitx5_running() { fcitx5-remote --check >/dev/null 2>&1; }
ibus_owned_by_fcitx5() { busctl --user list 2>/dev/null | awk '$1=="org.freedesktop.IBus"{print $3}' | grep -qx fcitx5; }
im_is_rime() { [[ $(fcitx5-remote -n 2>/dev/null) == rime ]]; }
env_is_fcitx() {
    local env
    env=$(systemctl --user show-environment 2>/dev/null) || return 1
    grep -qx 'XMODIFIERS=@im=fcitx' <<<"$env" && grep -qx 'QT_IM_MODULE=fcitx' <<<"$env"
}
kimpanel_enabled() { gnome-extensions list --enabled 2>/dev/null | grep -qx 'kimpanel@kde.org'; }
kimpanel_panel_alive() { busctl --user list 2>/dev/null | grep -q '^org.kde.impanel '; }
kimpanel_engine_alive() { busctl --user list 2>/dev/null | grep -q '^org.kde.kimpanel.inputmethod '; }
simplified_default() {
    local b="$HOME/.local/share/fcitx5/rime/build/luna_pinyin.schema.yaml"
    [[ -f $b ]] && grep -A1 'name: simplification' "$b" | grep -q 'reset: 1'
}

echo "fcitx5 + Rime verification"
check "fcitx5 is running"                  fcitx5_running
check "fcitx5 owns org.freedesktop.IBus"   ibus_owned_by_fcitx5
check "current input method is Rime"       im_is_rime
check "session env points at fcitx"        env_is_fcitx
check "kimpanel extension enabled"         kimpanel_enabled
check "kimpanel panel service present"     kimpanel_panel_alive
check "kimpanel engine service present"    kimpanel_engine_alive
check "Rime defaults to Simplified"        simplified_default

echo
if [[ $fail -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "Some checks failed. See README troubleshooting."
exit 1
