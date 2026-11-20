# AGENTS.md

Installer for **fcitx5 + Rime on Fedora GNOME (Wayland)**. Written so an AI agent can run it non-interactively and verify the result.

## Preconditions

- Fedora Linux with GNOME (tested: Fedora 45, GNOME Shell 51.1, Wayland).
- Run as the **desktop user**, never as root. The script calls `sudo` itself.
- If you are non-interactive (no TTY), sudo must be passwordless:
  `sudo -n true` must succeed. Otherwise the script exits with code 4 — do not try to bypass this.

## Run

```bash
git clone https://github.com/zjbfx/fcitx5-rime-fedora-gnome.git
cd fcitx5-rime-fedora-gnome
./install.sh
```

Options: `--no-kimpanel` (skip the GNOME Shell candidate-window extension), `-h`.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Installed and configured; **a logout/login is still required** |
| 1 | Runtime error |
| 2 | Bad usage |
| 3 | Unsupported distribution |
| 4 | sudo unavailable in a non-interactive context |

## Required follow-up (cannot be skipped)

After `install.sh` exits 0, the desktop user must **log out and log back in**. IM environment variables (`~/.config/environment.d`) and the newly installed GNOME extension are only applied on a fresh login. Do not report success before this happens.

After re-login, run:

```bash
./verify.sh
```

`verify.sh` exits 0 only when all of the following are true:

- fcitx5 is running and owns `org.freedesktop.IBus`
- the current input method is `rime`
- `XMODIFIERS=@im=fcitx` and `QT_IM_MODULE=fcitx` are in the session environment
- kimpanel extension is enabled and both kimpanel D-Bus services are alive
- Rime is configured to output Simplified Chinese

## What the script changes

- Installs packages via `sudo dnf install -y`: `fcitx5 fcitx5-rime brise fcitx5-configtool fcitx5-autostart fcitx5-gtk fcitx5-qt`.
- Writes user config (backs up any differing file to `*.bak.<timestamp>`):
  - `~/.config/environment.d/fcitx5.conf`
  - `~/.config/fcitx5/profile` (Rime as default)
  - `~/.local/share/fcitx5/rime/luna_pinyin.custom.yaml` (Simplified output, schema renamed to 明月拼音)
- Installs the kimpanel GNOME extension from extensions.gnome.org, choosing the release matching the installed GNOME Shell major version, and adds it to `org.gnome.shell enabled-extensions`. It does **not** install Fedora's `gnome-shell-extension-kimpanel` package (incompatible with GNOME Shell 51).
- Starts fcitx5 if it is not running and triggers a Rime redeploy.

It does **not** modify `/etc`, does not remove ibus packages, and does not change GNOME input sources.

## Safety / idempotency

- Safe to re-run; configuration is backed up, not lost.
- Uninstall: `./uninstall.sh` (add `--remove-packages` / `--purge` as needed).
- Do not edit the generated config files to "fix" failures before collecting `./verify.sh` output — the checks are the contract.

## Troubleshooting pointers

- Candidate window misplaced → kimpanel not active. Verify with `gnome-extensions list --enabled`.
- Top bar shows an odd character as the CN/EN indicator → Rime schema name is used; the installer sets it to 明月拼音 (label 明).
- fcitx5 not owning IBus → ensure `fcitx5-autostart` is installed and the user has re-logged in.
