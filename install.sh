#!/usr/bin/env bash
# fcitx5 + Rime installer for Fedora GNOME (tested: Fedora 45, GNOME Shell 51, Wayland).
# Idempotent. Run as your normal desktop user (the script calls sudo itself).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/configs"
PKGS=(fcitx5 fcitx5-rime brise fcitx5-configtool fcitx5-autostart fcitx5-gtk fcitx5-qt)
KIMPANEL_UUID="kimpanel@kde.org"
KIMPANEL_PK=261

WITH_KIMPANEL=1

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  warn\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

usage() {
    cat <<'EOF'
Usage: ./install.sh [--no-kimpanel]

  --no-kimpanel   Skip the GNOME Shell "Input Method Panel" (kimpanel) extension.
                  Without it, Rime works but candidate windows may be misplaced
                  on GNOME Wayland.
  -h, --help      Show this help.

Exit codes:
  0  success (log out / log back in to finish)
  1  runtime error
  2  bad usage
  3  unsupported distribution
  4  sudo unavailable in non-interactive mode
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-kimpanel) WITH_KIMPANEL=0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $arg" 2 ;;
    esac
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------- preflight
[[ ${EUID} -ne 0 ]] || die "Run as your desktop user, not root (this script calls sudo itself)."
[[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == fedora ]] || die "unsupported distribution '${ID:-unknown}'; this installer targets Fedora." 3
[[ ${XDG_SESSION_TYPE:-} == wayland ]] || warn "session is '${XDG_SESSION_TYPE:-unknown}', not Wayland; the setup is only tested on Wayland."
if [[ ${XDG_CURRENT_DESKTOP:-} != *GNOME* ]]; then
    warn "GNOME not detected; the kimpanel step is GNOME-only."
fi

command -v sudo >/dev/null 2>&1 || die "sudo not found"
if ! sudo -n true 2>/dev/null; then
    if [[ -t 0 && -t 1 ]]; then
        info "sudo requires a password"
        sudo -v
    else
        die "passwordless sudo is required for non-interactive installs. Run 'sudo -v' first or run this script in a terminal." 4
    fi
fi

# ---------------------------------------------------------------- packages
info "Installing packages: ${PKGS[*]}"
sudo dnf install -y "${PKGS[@]}"

# ---------------------------------------------------------------- user config
install_config() {
    local src=$1 dst=$2 backup
    mkdir -p -- "$(dirname -- "$dst")"
    if [[ -f $dst ]] && ! cmp -s -- "$src" "$dst"; then
        backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
        cp -a -- "$dst" "$backup"
        warn "existing $(basename -- "$dst") backed up to $backup"
    fi
    install -m 0644 -- "$src" "$dst"
}

info "Writing fcitx5 / Rime configuration"
install_config "$CONFIG_DIR/environment.d/fcitx5.conf" "$HOME/.config/environment.d/fcitx5.conf"
install_config "$CONFIG_DIR/fcitx5/profile"           "$HOME/.config/fcitx5/profile"
install_config "$CONFIG_DIR/rime/luna_pinyin.custom.yaml" "$HOME/.local/share/fcitx5/rime/luna_pinyin.custom.yaml"
ok "environment.d, fcitx5 profile, Rime simplification patch"

# ---------------------------------------------------------------- kimpanel
install_kimpanel() {
    local ver major info_json uuid version url zip cur new
    command -v gnome-shell >/dev/null 2>&1 || { warn "gnome-shell not found; skipping kimpanel"; return 0; }
    ver=$(gnome-shell --version 2>/dev/null | awk '{print $3}')
    major=${ver%%.*}
    [[ -n $major ]] || { warn "cannot detect GNOME Shell version; skipping kimpanel"; return 0; }

    info "Installing GNOME Shell kimpanel extension (Shell ${major})"
    info_json="$TMP_DIR/kimpanel-info.json"
    if ! curl -fsSL --max-time 20 \
        "https://extensions.gnome.org/extension-info/?pk=${KIMPANEL_PK}&shell_version=${major}" \
        -o "$info_json"; then
        warn "cannot reach extensions.gnome.org; skipping kimpanel"
        return 0
    fi

    read -r uuid version url < <(python3 - "$info_json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(0)
print(d.get("uuid") or "", d.get("version") or "", d.get("download_url") or "")
PY
)
    if [[ -z ${uuid:-} || -z ${url:-} ]]; then
        warn "no kimpanel release for GNOME Shell ${major}; skipping"
        return 0
    fi

    zip="$TMP_DIR/kimpanel.zip"
    curl -fsSL --max-time 30 "https://extensions.gnome.org${url}" -o "$zip" || {
        warn "kimpanel download failed; skipping"
        return 0
    }
    if ! python3 - "$zip" "$major" <<'PY'; then
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    meta = json.loads(z.read("metadata.json"))
assert meta.get("uuid") == "kimpanel@kde.org", "unexpected uuid"
versions = [str(v) for v in meta.get("shell-version", [])]
assert sys.argv[2] in versions, f"shell-version mismatch: {versions}"
PY
        warn "kimpanel package failed validation; skipping"
        return 0
    fi

    if ! gnome-extensions install --force "$zip" >/dev/null; then
        warn "gnome-extensions install failed; skipping kimpanel"
        return 0
    fi

    # The running shell does not rescan new extensions; register it so the next
    # login loads it. (gnome-extensions enable fails until after that login.)
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
if sys.argv[2] not in items:
    items.append(sys.argv[2])
print(str(items))
PY
)
    gsettings set org.gnome.shell enabled-extensions "$new"
    ok "kimpanel ${version} installed (activates after re-login)"
}

if [[ $WITH_KIMPANEL -eq 1 ]]; then
    install_kimpanel
fi

# ---------------------------------------------------------------- activate
info "Starting fcitx5"
if ! fcitx5-remote --check >/dev/null 2>&1; then
    fcitx5 -d >/dev/null 2>&1 || true
    sleep 2
fi

if ! fcitx5-remote --check >/dev/null 2>&1; then
    warn "fcitx5 is not running yet; it will autostart after you log back in"
else
    # Reloading the Rime addon triggers a Rime deployment of the new patch.
    busctl --user call org.fcitx.Fcitx5 /controller \
        org.fcitx.Fcitx.Controller1 ReloadAddonConfig s rime >/dev/null 2>&1 || true
    sleep 1
    fcitx5-remote -s rime >/dev/null 2>&1 || true
    im=$(fcitx5-remote -n 2>/dev/null || true)
    if [[ $im == rime ]]; then
        ok "Rime engine active"
    else
        warn "current input method is '${im:-unknown}'; profile defaults to Rime at next login"
    fi
    owner=$(busctl --user list 2>/dev/null | awk '$1=="org.freedesktop.IBus"{print $3}' | head -n1)
    if [[ $owner == fcitx5 ]]; then
        ok "fcitx5 replaced ibus-daemon on the IBus bus"
    else
        warn "org.freedesktop.IBus is owned by '${owner:-nobody}'; fcitx5 should take over at next login"
    fi
fi

build="$HOME/.local/share/fcitx5/rime/build/luna_pinyin.schema.yaml"
if [[ -f $build ]] && grep -A1 'name: simplification' "$build" | grep -q 'reset: 1'; then
    ok "Rime outputs Simplified Chinese by default"
else
    warn "Rime deployment pending; simplified output applies after re-login"
fi

cat <<'EOF'

==============================================================================
DONE.

REQUIRED NEXT STEP: log out of GNOME and log back in.
Environment variables (~/.config/environment.d) and the kimpanel extension only
take effect in a new session.

After re-login run:
    ./verify.sh

Usage:
    Ctrl+Space        switch Chinese / English
    Ctrl+Shift+4      toggle Simplified / Traditional (default: Simplified)

If the top bar shows a garbled Chinese/English symbol, see README troubleshooting.
==============================================================================
EOF
