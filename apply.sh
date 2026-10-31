#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
done_() { printf '    \033[32mok\033[0m  %s\n' "$*"; }
note() { printf '    \033[33m!!\033[0m  %s\n' "$*"; }
in_container() { [ -f /run/.toolboxenv ] || [ -f /run/.containerenv ]; }

in_container && { echo "Run apply.sh on the host, not inside a toolbox." >&2; exit 1; }
SUDO=sudo
# a file called .lean next to apply.sh (put there by build-iso.sh lean) skips the big optional apps
LEAN=0; [ -e "$HERE/.lean" ] && LEAN=1
if [ "$(id -u)" -eq 0 ]; then
    [ "$*" = system ] || { echo "Run apply.sh as your user (as root only: apply.sh system)." >&2; exit 1; }
    SUDO=""
fi

sys_put() {
    local src=$1 dst=$2 mode=${3:-0644}
    if $SUDO cmp -s "$src" "$dst" 2>/dev/null; then done_ "$dst"; return 1; fi
    [ -e "$dst" ] && $SUDO cp -a "$dst" "$dst.bak"
    $SUDO install -D -m "$mode" "$src" "$dst"
    done_ "$dst (updated)"
    return 0
}

do_system() {
    say "system (sudo)"
    [ -z "$SUDO" ] || $SUDO -n true 2>/dev/null || $SUDO -v

    if [ "$LEAN" = 0 ]; then
        sys_put "$HERE/etc/yum.repos.d/vscode.repo" /etc/yum.repos.d/vscode.repo || true
        rpm -q code >/dev/null 2>&1 || $SUDO dnf -y install code
    fi
    # the login session entry comes from sway-config-fedora, which we do not install (it pulls in Waybar)
    sys_put "$HERE/etc/wayland-sessions/sway.desktop" /usr/share/wayland-sessions/sway.desktop || true
    if sys_put "$HERE/etc/yum.repos.d/sway-rpm.repo" /etc/yum.repos.d/sway-rpm.repo || ! rpm -q gpg-pubkey-49c90df85566d034 >/dev/null 2>&1; then
        $SUDO rpm --import "$HERE/install/rpms/RPM-GPG-KEY-sway-rpm.asc"
    fi
    if sway --version 2>/dev/null | grep -q ' 1\.1[2-9]'; then done_ "sway $(sway --version | awk '{print $3}') (sway-rpm)"
    else
        $SUDO dnf -y --refresh install sway wlroots sway-config-minimal
        $SUDO dnf -y upgrade sway wlroots sway-config-minimal   # Fedora's own 1.11 may already be installed: install alone keeps it
        if sway --version 2>/dev/null | grep -q ' 1\.1[2-9]'; then done_ "sway $(sway --version | awk '{print $3}') (installed from sway-rpm)"
        else note "sway 1.12 NOT installed (have $(rpm -q sway)); check the sway-rpm repo and run apply.sh system again"; fi
    fi
    if [ "$LEAN" = 0 ]; then done_ "VS Code $(rpm -q --qf '%{VERSION}' code)"; else done_ "VS Code skipped (lean build)"; fi

    local extra=(dconf fwupd-efi fwupd-plugin-uefi-capsule-data gnome-software PackageKit rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data
                 libayatana-appindicator-gtk3 plymouth-system-theme gh gnome-keyring-pam lynis
                 google-noto-nastaliq-urdu-fonts google-noto-sans-arabic-vf-fonts google-noto-naskh-arabic-vf-fonts
                 google-noto-sans-cjk-fonts google-noto-serif-cjk-fonts google-noto-sans-thai-vf-fonts
                 google-noto-sans-bengali-vf-fonts google-noto-color-emoji-fonts dejavu-sans-fonts
                 dejavu-sans-mono-fonts dejavu-serif-fonts adwaita-sans-fonts adwaita-mono-fonts
                 xdg-desktop-portal-gtk pipewire-gstreamer cups-pk-helper gutenprint-cups kf6-kimageformats alsa-utils btop
                 sway sway-config-minimal sway-systemd swaybg grim grimshot slurp brightnessctl
                 pulseaudio-utils lxqt-policykit xdg-desktop-portal-wlr
                 ffmpeg gstreamer1-plugin-libav gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld) missing=() p
    for p in "${extra[@]}"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -gt 0 ]; then
        $SUDO dnf -y -q --setopt=install_weak_deps=False --setopt=fastestmirror=True \
            install --allowerasing "${missing[@]}" && done_ "extra packages (installed: ${missing[*]})"
    else done_ "extra packages (fonts, portal, printing, codecs, btop)"; fi

    if [ "$(plymouth-set-default-theme 2>/dev/null)" = bgrt ]; then done_ "boot screen: bgrt"
    else $SUDO plymouth-set-default-theme -R bgrt && done_ "boot screen: bgrt (updated, initramfs rebuilt)"; fi

    sys_put "$HERE/etc/local-bin/sudoless" /usr/local/bin/sudoless 0755 || true

    if sys_put "$HERE/etc/udev/rules.d/60-i2c-display.rules" /etc/udev/rules.d/60-i2c-display.rules; then
        $SUDO udevadm control --reload && $SUDO udevadm trigger --subsystem-match=i2c-dev || true
    fi

    if lspci -n 2>/dev/null | grep -qE ' 030[02]: 10de:'; then
        if rpm -q nvidia-kmod-control nvidia-kmod-guard >/dev/null 2>&1 || [ -f /etc/yum.repos.d/nvidia-kmod-rpm.repo ]; then
            $SUDO dnf -y -q remove nvidia-kmod-control nvidia-kmod-guard >/dev/null 2>&1 || true
            $SUDO rm -f /etc/yum.repos.d/nvidia-kmod-rpm.repo
            done_ "old prebuilt NVIDIA module repo removed"
        fi
        if rpm -q akmod-nvidia >/dev/null 2>&1; then done_ "akmod-nvidia"
        else
            $SUDO dnf -y -q --setopt=install_weak_deps=False install akmod-nvidia "kernel-devel-$(uname -r)" \
                && done_ "akmod-nvidia (installed)"
            $SUDO akmods --force --kernels "$(uname -r)" >/dev/null && done_ "NVIDIA module built for $(uname -r)"
        fi
        sys_put "$HERE/etc/local-bin/prime-run" /usr/local/bin/prime-run 0755 || true

        local nv_args="rd.driver.blacklist=nouveau,nova_core modprobe.blacklist=nouveau,nova_core nvidia-drm.modeset=1 nvidia-drm.fbdev=1" k
        for k in /boot/vmlinuz-*; do
            [[ $k == *rescue* ]] && continue
            if $SUDO grubby --info="$k" | grep -q 'modprobe.blacklist=nouveau'; then done_ "nouveau blacklisted: ${k#/boot/vmlinuz-}"
            else $SUDO grubby --update-kernel="$k" --args="$nv_args" && done_ "nouveau blacklisted: ${k#/boot/vmlinuz-} (updated)"; fi
        done
        if ! grep -q '^GRUB_CMDLINE_LINUX=.*modprobe.blacklist=nouveau' /etc/default/grub; then
            $SUDO sed -i "s/^GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 $nv_args\"/" /etc/default/grub
            done_ "/etc/default/grub: nouveau blacklisted (updated)"
        fi
    else
        note "no NVIDIA card: skipped the memory clock service"
    fi

    if grep -q '^installonly_limit=2$' /etc/dnf/dnf.conf; then done_ "dnf keeps 2 kernels"
    else
        $SUDO sed -i '/^installonly_limit=/d' /etc/dnf/dnf.conf
        echo 'installonly_limit=2' | $SUDO tee -a /etc/dnf/dnf.conf >/dev/null
        done_ "dnf keeps 2 kernels (updated)"
    fi

    local font=/boot/grub2/fonts/adwaita-mono-48.pf2 regen=0
    sys_put "$HERE/assets/grub-adwaita-mono-48.pf2" "$font" && regen=1
    if ! grep -q "^GRUB_FONT=$font\$" /etc/default/grub; then
        $SUDO sed -i '/^GRUB_FONT=/d' /etc/default/grub
        echo "GRUB_FONT=$font" | $SUDO tee -a /etc/default/grub >/dev/null
        regen=1
    fi
    local kv
    for kv in GRUB_TERMINAL_OUTPUT=gfxterm GRUB_GFXMODE=auto GRUB_GFXPAYLOAD_LINUX=keep; do
        grep -q "^${kv%%=*}=\"\?${kv#*=}\"\?\$" /etc/default/grub && continue
        $SUDO sed -i "/^${kv%%=*}=/d" /etc/default/grub
        echo "${kv%%=*}=\"${kv#*=}\"" | $SUDO tee -a /etc/default/grub >/dev/null
        regen=1
    done
    if [ "$regen" = 1 ]; then $SUDO grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 && done_ "GRUB config regenerated"
    else done_ "GRUB font"; fi

    local cc=/etc/chromium/chromium.conf
    if [ -f "$cc" ]; then
        $SUDO sed -i '/^# >>> my_system:/,/^# <<< my_system <<<$/d' "$cc"
        $SUDO tee -a "$cc" < "$HERE/etc/chromium/chromium.conf.d-my_system" >/dev/null
        done_ "Chromium: per-user flags file (Google sign-in)"
    fi

    local rel ls_ver ls_have ls_sum tmp
    rel=$(curl -fsSL https://api.github.com/repos/localsend/localsend/releases/latest) || rel=""
    ls_ver=$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' <<<"$rel" 2>/dev/null) || ls_ver=""
    ls_have=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' /opt/localsend/data/flutter_assets/version.json 2>/dev/null) || ls_have=""
    if [ -z "$ls_ver" ]; then note "LocalSend: GitHub not reachable; left as it is (${ls_have:-not installed})"
    elif [ "$ls_have" = "$ls_ver" ]; then done_ "LocalSend $ls_ver"
    else
        local ls_tgz="LocalSend-$ls_ver-linux-x86-64.tar.gz"
        ls_sum=$(python3 -I -c "import json,sys; print([a['digest'] for a in json.load(sys.stdin)['assets'] if a['name']=='$ls_tgz'][0].split(':')[1])" <<<"$rel")
        tmp=$(mktemp -d)
        curl -fsSL -o "$tmp/$ls_tgz" "https://github.com/localsend/localsend/releases/download/v$ls_ver/$ls_tgz"
        if echo "$ls_sum  $tmp/$ls_tgz" | sha256sum -c --status; then
            $SUDO rm -rf /opt/localsend.new && $SUDO mkdir -p /opt/localsend.new
            $SUDO tar -xzf "$tmp/$ls_tgz" -C /opt/localsend.new --no-same-owner
            $SUDO rm -rf /opt/localsend && $SUDO mv /opt/localsend.new /opt/localsend
            done_ "LocalSend $ls_ver (installed, SHA-256 checked)"
        else note "LocalSend: SHA-256 mismatch, not installed"; fi
        rm -rf "$tmp"
    fi
    if [ -x /opt/localsend/localsend_app ]; then
        $SUDO ln -sfn /opt/localsend/localsend_app /usr/local/bin/localsend
        $SUDO install -D -m 0644 /opt/localsend/data/flutter_assets/assets/img/logo-512.png \
            /usr/local/share/icons/hicolor/512x512/apps/localsend.png
        $SUDO rm -f /usr/local/share/applications/localsend.desktop
        sys_put "$HERE/etc/localsend/org.localsend.localsend_app.desktop" \
            /usr/local/share/applications/org.localsend.localsend_app.desktop || true
    fi

    local fw_changed=0 r fw=(firewall-cmd --permanent)
    $SUDO firewall-cmd --state >/dev/null 2>&1 || fw=(firewall-offline-cmd)
    if $SUDO "${fw[@]}" --query-service=ssh >/dev/null 2>&1; then
        $SUDO "${fw[@]}" --remove-service=ssh >/dev/null && fw_changed=1
    fi
    r='rule service name="ssh" accept limit value="6/m"'
    $SUDO "${fw[@]}" --query-rich-rule="$r" >/dev/null 2>&1 \
        || { $SUDO "${fw[@]}" --add-rich-rule="$r" >/dev/null && fw_changed=1; }
    for r in http https; do
        $SUDO "${fw[@]}" --query-service=$r >/dev/null 2>&1 \
            || { $SUDO "${fw[@]}" --add-service=$r >/dev/null && fw_changed=1; }
    done
    for r in 53317/tcp 53317/udp; do
        $SUDO "${fw[@]}" --query-port=$r >/dev/null 2>&1 \
            || { $SUDO "${fw[@]}" --add-port=$r >/dev/null && fw_changed=1; }
    done
    if [ "$fw_changed" = 1 ]; then
        [ "${fw[0]}" = firewall-cmd ] && $SUDO firewall-cmd --reload >/dev/null
        done_ "firewall rules (updated)"
    else done_ "firewall rules"; fi
}

# gh_release_asset REPO REGEX OUTFILE: download a latest-release file from GitHub and install it only if its
# SHA-256 matches the digest GitHub publishes for that file.
gh_release_asset() {
    local repo=$1 pat=$2 out=$3 rel name url sum
    rel=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest") || return 1
    read -r name url sum < <(python3 -I -c '
import json, re, sys
d = json.load(sys.stdin); pat = re.compile(sys.argv[1], re.I)
for a in d["assets"]:
    if pat.fullmatch(a["name"]) and (a.get("digest") or "").startswith("sha256:"):
        print(a["name"], a["browser_download_url"], a["digest"][7:]); break' "$pat" <<<"$rel") || return 1
    [ -n "${name:-}" ] || return 1
    curl -fsSL -o "$out" "$url" || return 1
    echo "$sum  $out" | sha256sum -c --status
}

link() {
    local src="$HERE/$1" dst="$HOME/$2"
    if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then done_ "~/$2"; return; fi
    mkdir -p "$(dirname "$dst")"
    [ -e "$dst" ] || [ -L "$dst" ] && mv "$dst" "$dst.bak.$(date +%s)"
    ln -s "$src" "$dst"
    done_ "~/$2 -> my_system (linked)"
}

do_home() {
    say "home"
    link home/.bashrc.d/custom.sh .bashrc.d/custom.sh
    link home/.config/nvim .config/nvim
    link home/.config/fastfetch .config/fastfetch
    link home/.config/fontconfig .config/fontconfig
    link home/.config/starship.toml .config/starship.toml
    if [ -f "$HOME/.local/bin/sudoless" ] && [ ! -L "$HOME/.local/bin/sudoless" ]; then
        mv "$HOME/.local/bin/sudoless" "$HOME/.local/bin/sudoless.bak" && done_ "~/.local/bin/sudoless -> .bak (now /usr/local/bin/sudoless)"
    fi
    [ -f "$HOME/.gitconfig" ] || { cp "$HERE/home/.gitconfig" "$HOME/.gitconfig"; done_ "~/.gitconfig (copied)"; }

    local cf="$HOME/.config/chromium-flags.conf" f
    mkdir -p "$HOME/.config"; touch "$cf"
    for f in --oauth2-client-id=77185425430.apps.googleusercontent.com \
             --oauth2-client-secret=OTJgUOQcT7lO7GsGZq2G4IlT; do
        grep -qxF -- "$f" "$cf" || echo "$f" >> "$cf"
    done
    done_ "Chromium Google sign-in (~/.config/chromium-flags.conf)"

    mkdir -p "$HOME/.local/share/fonts"
    if rsync -a --itemize-changes "$HERE/home/.local/share/fonts/" "$HOME/.local/share/fonts/" | grep -q .; then
        fc-cache -f >/dev/null 2>&1; done_ "fonts (installed)"
    else done_ "fonts"; fi

    local wd="$HOME/Pictures/Wallpapers" wcur w wn=0
    mkdir -p "$wd"
    for w in "$HERE"/home/Pictures/Wallpapers/*.{jpg,png}; do
        [ -f "$w" ] || continue
        compgen -G "$wd/$(basename "${w%.*}").*" >/dev/null && continue
        cp "$w" "$wd/" && wn=$((wn + 1))
    done
    if [ "$wn" -gt 0 ]; then done_ "wallpapers ($wn copied to ~/Pictures/Wallpapers)"
    else done_ "wallpapers"; fi
    local lsp="$HOME/.local/share/org.localsend.localsend_app/shared_preferences.json"
    if python3 -I - "$lsp" <<'EOF'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
if d.get("flutter.ls_minimize_to_tray") is True:
    sys.exit(0)
d["flutter.ls_minimize_to_tray"] = True
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"))
sys.exit(1)
EOF
    then done_ "LocalSend: close to tray"
    else done_ "LocalSend: close to tray (updated)"; fi

    if ! command -v gh >/dev/null; then note "gh not installed yet: run apply.sh system"
    elif ! gh auth status >/dev/null 2>&1; then note "gh not logged in: run 'gh auth login', then apply.sh home"
    elif git config --global --get-all credential.https://github.com.helper 2>/dev/null | grep -q 'gh auth git-credential'; then
        done_ "gh: git uses it for GitHub"
    else gh auth setup-git && done_ "gh: git uses it for GitHub (updated)"; fi

    local pf='JetBrainsMono Nerd Font Mono 12'
    if [ "$(gsettings get org.gnome.Ptyxis use-system-font 2>/dev/null)" = false ] \
       && [ "$(gsettings get org.gnome.Ptyxis font-name 2>/dev/null)" = "'$pf'" ]; then done_ "Ptyxis font: $pf"
    else
        gsettings set org.gnome.Ptyxis use-system-font false && gsettings set org.gnome.Ptyxis font-name "$pf" \
            && done_ "Ptyxis font: $pf (updated)" || note "could not set the Ptyxis font (no desktop session?)"
    fi

    link home/.config/sway/config .config/sway/config
    local f
    mkdir -p "$HOME/.config/sway/config.d"
    find "$HOME/.config/sway/config.d" -xtype l -delete
    for f in home/.config/sway/config.d/*.conf; do link "$f" ".config/sway/config.d/${f##*/}"; done
    swaymsg reload >/dev/null 2>&1 || true
    local ds="$HOME/.config/dms/settings.json" dmark="$HOME/.local/state/my_system/dms-settings.applied"
    mkdir -p "$HOME/.config/dms" "${dmark%/*}"
    if [ ! -f "$dmark" ]; then
        [ -f "$ds" ] && cp "$ds" "$ds.bak"
        cp "$HERE/home/.config/dms/settings.json" "$ds" && touch "$dmark"
        done_ "DMS settings (copied from the repo, once)"
    elif cmp -s "$HERE/home/.config/dms/settings.json" "$ds"; then done_ "DMS settings"
    else done_ "DMS settings (live ones kept; to save them: cp $ds $HERE/home/.config/dms/)"; fi

    link home/.local/bin/open-here-cwd .local/bin/open-here-cwd
    link home/.local/bin/open-here-toolbox .local/bin/open-here-toolbox
    link home/.config/dms/plugins/OpenHere .config/dms/plugins/OpenHere
    link home/.config/dms/plugins/Switcher .config/dms/plugins/Switcher
    link home/.config/dms/plugins/Doctor .config/dms/plugins/Doctor
    local ps="$HOME/.config/dms/plugin_settings.json" psr=0 pl
    for pl in openHere:"Open Here" switcher:"Window Switcher" doctor:"System Doctor"; do
        psr=0
        python3 -I - "$ps" "${pl%%:*}" 2>/dev/null <<'PYEOF' || psr=$?
import json, os, sys
f, pid = sys.argv[1:]
d = json.load(open(f)) if os.path.isfile(f) and os.path.getsize(f) else {}
if "enabled" in d.get(pid, {}):
    sys.exit(2)
d.setdefault(pid, {})["enabled"] = True
json.dump(d, open(f, "w"), indent=2)
PYEOF
        if [ "$psr" = 0 ]; then
            dms ipc call plugin-scan scan >/dev/null 2>&1 && sleep 1 && dms ipc call plugins enable "${pl%%:*}" >/dev/null 2>&1 || true
            done_ "${pl#*:} plugin enabled (updated)"
        elif [ "$psr" = 2 ]; then done_ "${pl#*:} plugin enabled"
        else note "${pl#*:}: could not read $ps (enable it in DMS → Plugins)"; fi
    done

    rpm -q dconf >/dev/null 2>&1 && done_ "dconf (where GSettings are saved)" \
        || note "dconf is not installed: light/dark settings are lost (add it to the system packages)"
    link home/.local/bin/sway-keys .local/bin/sway-keys
    link home/.local/bin/ptyxis-e .local/bin/ptyxis-e
    link home/.local/bin/sway-colors-apply .local/bin/sway-colors-apply
    link home/.config/matugen/config.toml .config/matugen/config.toml
    link home/.config/matugen/templates .config/matugen/templates
    link home/.local/bin/open-with .local/bin/open-with
    link home/.local/share/applications/open-with.desktop .local/share/applications/open-with.desktop
    link home/.local/bin/screenshot-notify .local/bin/screenshot-notify
    link home/.local/bin/onlyoffice-run .local/bin/onlyoffice-run
    sd=/usr/share/applications/onlyoffice-desktopeditors.desktop
    ud="$HOME/.local/share/applications/onlyoffice-desktopeditors.desktop"
    if [ -f "$sd" ]; then
        mkdir -p "$(dirname "$ud")"
        sed -E "s|^Exec=/usr/bin/onlyoffice-desktopeditors|Exec=$HOME/.local/bin/onlyoffice-run --system-title-bar|" "$sd" > "$ud.new"
        if cmp -s "$ud.new" "$ud"; then rm -f "$ud.new"; done_ "OnlyOffice launcher (--system-title-bar)"
        else mv "$ud.new" "$ud"; done_ "OnlyOffice launcher (--system-title-bar, updated)"; fi
    fi
    if [ "$(xdg-mime query default application/octet-stream 2>/dev/null)" = open-with.desktop ]; then
        done_ "unknown files ask which app to open with"
    else
        xdg-mime default open-with.desktop application/octet-stream \
            && done_ "unknown files ask which app to open with (updated)" || note "could not set the handler for unknown files"
    fi
    systemctl --user daemon-reload
    local scheme portal
    case "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" in
        "'prefer-dark'") scheme=1 ;; "'prefer-light'") scheme=2 ;; *) scheme=0 ;;
    esac
    portal=$(busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
        org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>/dev/null | awk '{print $3}')
    if [ -z "$portal" ]; then note "settings portal not running (no desktop session?)"
    elif [ "$portal" = "$scheme" ]; then done_ "portal color-scheme matches GSettings ($portal)"
    else
        systemctl --user restart xdg-desktop-portal-gnome.service xdg-desktop-portal-gtk.service xdg-desktop-portal.service \
            && done_ "portal color-scheme (restarted; it was stale)"
    fi
    mkdir -p "$HOME/.local/bin"
    if [ -x "$HOME/.local/bin/starship" ]; then done_ "starship $("$HOME/.local/bin/starship" --version | head -1 | cut -d' ' -f2)"
    else
        tmp=$(mktemp -d)
        if gh_release_asset starship/starship 'starship-x86_64-unknown-linux-gnu\.tar\.gz' "$tmp/starship.tgz" \
           && tar -xzf "$tmp/starship.tgz" -C "$tmp" starship && install -m 755 "$tmp/starship" "$HOME/.local/bin/starship"; then
            done_ "starship (installed, SHA-256 checked)"
        else note "starship: download or SHA-256 check failed, not installed; run apply.sh home again"; fi
        rm -rf "$tmp"
    fi

    if [ "$LEAN" = 1 ]; then done_ "Antigravity skipped (lean build)"
    else
        if [ ! -x "$HOME/.local/bin/agy" ]; then
            curl -fsSL https://antigravity.google/cli/install.sh | bash >/dev/null 2>&1 \
                || note "Antigravity installer failed (network?); run apply.sh home again"
        fi
        done_ "agy $("$HOME/.local/bin/agy" --version 2>/dev/null)"
    fi

    if [ "$LEAN" = 1 ]; then done_ "Claude Code skipped (lean build)"
    else
        if [ ! -x "$HOME/.local/bin/claude" ]; then
            curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
                || note "Claude Code installer failed (network?); run apply.sh home again"
        fi
        done_ "claude $("$HOME/.local/bin/claude" --version 2>/dev/null | cut -d' ' -f1)"
    fi
}

do_toolbox() {
    say "toolbox: dev"
    if ! podman container exists dev 2>/dev/null; then
        toolbox create -y -c dev --distro fedora --release "$(rpm -E %fedora)"
    fi
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$HERE/toolbox/dev-packages.txt")
    toolbox run -c dev sudo dnf -y -q --setopt=install_weak_deps=False install "${pkgs[@]}"
    done_ "${#pkgs[@]} dev packages"
    toolbox run -c dev sudo ln -sf /usr/bin/flatpak-xdg-open /usr/local/bin/xdg-open \
        && done_ "xdg-open in dev opens the host browser"

    if [ -x "$HOME/.local/bin/lazygit" ]; then done_ "lazygit"
    else
        local tmp
        tmp=$(mktemp -d)
        if gh_release_asset jesseduffield/lazygit 'lazygit_[0-9.]+_linux_x86_64\.tar\.gz' "$tmp/lg.tgz" \
           && tar -xzf "$tmp/lg.tgz" -C "$tmp" lazygit && install -m 755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"; then
            done_ "lazygit (installed, SHA-256 checked)"
        else note "lazygit: download or SHA-256 check failed, not installed; run apply.sh toolbox again"; fi
        rm -rf "$tmp"
    fi
    grep -q '^prefix=' "$HOME/.npmrc" 2>/dev/null || echo "prefix=$HOME/.local" >> "$HOME/.npmrc"
    toolbox run -c dev bash -c 'command -v neovim-node-host >/dev/null || npm install -g -s neovim' && done_ "neovim node provider"
}

do_nvim() {
    say "nvim: plugins, LSPs, parsers (inside dev)"
    toolbox run -c dev nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1
    done_ "plugins synced (lazy-lock.json)"
    local out try
    for try in 1 2 3; do
        out=$(toolbox run -c dev bash -c "cd '$HERE/nvim-setup' && nvim --headless -c 'luafile install-all.lua'" 2>&1) || true
        grep -q 'mason: .*failures: none' <<<"$out" && break
        [ "$try" -lt 3 ] && note "Mason reported failures; retrying ($try/3)"
    done
    if grep -qE '(mason|treesitter):' <<<"$out"; then
        grep -oE '(mason|treesitter): .*' <<<"$out" | sed 's/^/    /'
    else
        note "Mason/treesitter installer gave no summary; its last lines:"
        tail -15 <<<"$out" | sed 's/^/        /'
    fi
    toolbox run -c dev nvim --headless "+checkhealth" "+w! /tmp/checkhealth.txt" +qa >/dev/null 2>&1 || true
    local errs; errs=$(toolbox run -c dev grep -c 'ERROR' /tmp/checkhealth.txt 2>/dev/null || echo "?")
    done_ ":checkhealth ERROR lines: $errs (full report: toolbox run -c dev cat /tmp/checkhealth.txt)"
}

steps=("$@"); [ ${#steps[@]} -gt 0 ] || steps=(system home toolbox nvim)
for s in "${steps[@]}"; do
    case "$s" in
        system|home|toolbox|nvim) "do_$s" ;;
        *) echo "unknown step: $s (system, home, toolbox, nvim)" >&2; exit 2 ;;
    esac
done
say "done"
