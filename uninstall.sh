#!/usr/bin/env bash
# Remove what install.sh added. User data under ~/.local/share/fcitx5/rime is kept
# unless --purge is given.
set -euo pipefail

REMOVE_PKGS=0
PURGE=0
KIMPANEL_UUID="kimpanel@kde.org"

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [--remove-packages] [--purge]

  --remove-packages  Also uninstall the fcitx5 / Rime packages (sudo dnf remove).
  --purge            Also delete ~/.local/share/fcitx5 (Rime user dictionary).
  -h, --help         Show this help.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --remove-packages) REMOVE_PKGS=1 ;;
        --purge) PURGE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

info "Stopping fcitx5 (if running)"
fcitx5-remote -e >/dev/null 2>&1 || true

info "Removing user configuration"
rm -f -- "$HOME/.config/environment.d/fcitx5.conf" \
        "$HOME/.config/fcitx5/profile" \
        "$HOME/.local/share/fcitx5/rime/luna_pinyin.custom.yaml"

info "Disabling and removing kimpanel"
cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
new=$(python3 - "$cur" "$KIMPANEL_UUID" <<'PY'
import ast, sys
s = sys.argv[1].strip()
if s.startswith("@as "):
    s = s[4:]
try:
    items = ast.literal_eval(s)
except Exception:
    items = []
items = [i for i in items if i != sys.argv[2]]
print(str(items))
PY
)
gsettings set org.gnome.shell enabled-extensions "$new"
rm -rf -- "$HOME/.local/share/gnome-shell/extensions/${KIMPANEL_UUID}"

if [[ $PURGE -eq 1 ]]; then
    info "Purging ~/.local/share/fcitx5"
    rm -rf -- "$HOME/.local/share/fcitx5"
fi

if [[ $REMOVE_PKGS -eq 1 ]]; then
    info "Removing packages"
    sudo dnf remove -y fcitx5 fcitx5-rime brise fcitx5-configtool fcitx5-autostart fcitx5-gtk fcitx5-qt
fi

cat <<'EOF'

Uninstall complete. Log out and back in to restore the GNOME ibus input method.
EOF
