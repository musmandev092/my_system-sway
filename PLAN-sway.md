# Plan: my_system on Sway 1.12 + DMS

Goal: the same my_system install as before (Fedora 44, encrypted disk, NVIDIA, GNOME apps), with
Sway 1.12 instead of niri, the Fedora Sway spin key bindings, and DMS as the whole shell.

## Decisions

| Topic | Choice |
| --- | --- |
| Compositor | Sway 1.12 + wlroots 0.20 (rebuilt from Rawhide, shipped in `install/rpms/`) |
| Key bindings | Fedora Sway spin (`sway-config-fedora`, untouched in `/etc/sway`) + FedoraDesk additions |
| Shell | DMS: bar, launcher, notifications, clipboard, wallpaper, night light, lock, power menu |
| Login screen | `dms-greeter` on greetd, started with `--command sway` |
| Lock screen | DMS lock (`dms ipc call lock lock`) through swayidle; swaylock is installed but never used |
| Apps | GNOME family as before (Nautilus, Sushi, Ptyxis, Papers, Loupe, ...) |
| Not used | niri, niri-layout, Waybar, Rofi, Dunst, SDDM, Thunar, foot |

## Layout of the Sway config (all in `home/.config/sway/`)

- `config`: the Fedora spin's key bindings (copied from sway-config-fedora 0.4.3 and edited): terminal = Ptyxis,
  launcher = DMS, vertical split on `Super+Shift+v`, no rofi / waybar / swaylock / swaybg. Includes
  `/etc/sway/config.d/*.conf` (sway-systemd) and then `config.d/`.
- `config.d/`: spin defaults kept (`50-rules-browser`, `50-rules-policykit-agent`, `60-bindings-screenshot`,
  `65-mode-passthrough`, `95-*` autostarts) and yours: `60-input`, `70-appearance`, `71-dms-colors`,
  `80-keybindings`, `91-dms`, `92-switcher`.
- Gone: `10-outputs` (DMS display profiles do monitors), `90-bar`, `90-swayidle` (DMS idle lock: lock 5 min,
  screens off 10 min), `environment` (no GPU flags).
- `sway-config-minimal` (10 KB, built by sway-rpm to match Sway 1.12) is installed only to satisfy sway's `sway-config` requirement; Waybar is never installed.

## Key decisions (asked one by one)

Order of priority: 1. Fedora Sway spin keys (all kept) 2. DMS default keys 3. your dotfiles.

- Spin: all kept. Clashes: `Super+v` clipboard (DMS) -> vertical split moves to `Super+Shift+v`;
  `Super+Alt+c` is the colour picker; `Super+Space` stays the spin's focus swap.
- Hardware keys (volume, mic, brightness, media): DMS. Print screenshots: spin (grimshot).
- DMS keys kept: `Super+d` launcher, `Super+x` power menu, `Super+Alt+n` night light, `Super+y` wallpapers,
  `Super+v` clipboard, `Super+m` media, `Super+n` notepad, `Super+Shift+n` notepad expanded,
  `Super+Ctrl+n` notifications, `Super+Alt+l` lock, `Super+Alt+i` idle inhibit, `Super+p` display profile,
  `Ctrl+Alt+Delete` / `Ctrl+Alt+m` task manager, `Alt+Space` spotlight bar, `Super+,` settings.
  Skipped: rename workspace.
- Dotfiles kept: `Super+Shift+s` area screenshot, `Super+Ctrl+Left/Right` workspace (moved from Super+Tab),
  `Super`+wheel, 3-finger swipe (workspace), 4-finger swipe (focus), `Super+z` Open Here, calculator key,
  `Super+Return` Ptyxis. Skipped: emoji, theme toggle, NVIDIA clock key, WASD, app keys (Files, browser, Claude, btop).
- Built: Windows 11 style switcher. `Super+Tab` = overview of all workspaces with previews of their
  apps; `Alt+Tab` = switcher for the windows of the current workspace with previews. Needs a DMS plugin.
- Built: `Super+/` = shortcut list for the spin, DMS and your own keys together.
- Removed from the setup: `nvidia-mem-lock.service` (no GPU memory clock lock on Sway).
- Sway 1.12 comes from a new public repo `musmandev092/sway-rpm` (GitHub Pages, new GPG key, weekly auto-rebuild
  from Rawhide); not created yet.
- Both ISOs (dual boot and erase disk); Sway only, no niri.

## Packages and default apps (asked one by one)

- Fresh install is about 1,065 packages: roughly 2 GiB to download, 5 GiB installed (dry run; Claude Desktop not counted).
- Terminal: Ptyxis only (no foot). Browsers: Brave, Chromium and Edge all stay; default browser is Brave.
- `pavucontrol` removed (DMS has audio controls). `xdg-desktop-portal-gnome` stays because Claude Desktop requires it.
- All small GNOME apps stay (Snapshot, Clocks, Seahorse, Font Viewer); nothing added.

## Look and feel (asked one by one)

- Sway window title bars (kept from FedoraDesk: 1 px border, padding, Adwaita Sans) now follow the DMS theme:
  `home/.config/matugen/` holds a template that DMS runs on every theme change; it writes
  `~/.config/sway/dms-colors.conf` and `sway-colors-apply` repaints the running Sway without a reload.
  Catppuccin colours in `70-appearance.conf` are only the fallback before DMS writes the file.
- DMS corners: fixed radius 1 (was 12); Sway windows are square anyway. Animations: durations 40/30/30/40 ms
  (were 80/60/60/80) and Reduce motion on. Change in DMS Settings > Typography & Motion.

## Found by testing (all fixed in the repo)

- Sway 1.12 shows a red "errors in your config file" banner when a binding overrides an existing one. All my
  overriding bindsyms now use `--no-warn` (80-keybindings.conf, 91-dms.conf); the banner is gone.
- matugen refused `~/.config/matugen/config.toml` without a `[config]` section, so DMS never wrote the Sway
  title-bar colours. Fixed; DMS now regenerates `~/.config/sway/dms-colors.conf` on every theme change
  (checked: light gives #186584, dark gives #8dcff2 on this machine).
- DMS's own shortcut window only reads `~/.config/sway/config`, which we do not have. `Super+/` now opens a list
  inside the Switcher plugin (98 shortcuts with names; Esc closes, Up/Down scroll).
- `sway-session.target` must not be started in a test next to another session; tests run in an isolated headless
  Sway with its own dbus and runtime dir.
- The Alt+Tab / Super+Tab / shortcut-list cards use DMS's corner radius and theme colours (radius 1 now), set in
  `SwitcherDaemon.qml`, so they always match DMS Settings.
- The idle lock (5 minutes) really locks the screen. It is meant to; unlock with your password.

## Notes to check during the VM test

- Nouveau / nova_core: the two files `etc/modprobe.d/blacklist-nouveau.conf` and `etc/dracut.conf.d/90-omit-nouveau.conf`
  are removed from the setup (your choice). After the VM install, check with a (fake or passed-through) NVIDIA GPU
  whether nouveau and nova_core end up blacklisted by the driver package and the kernel flags alone:
  `tr ' ' '\n' < /proc/cmdline | grep -E 'nouveau|nova'` and `lsmod | grep -E 'nouveau|nova_core'`.
  If either module loads, bring the files back.

## Config decisions, one by one (final)

Kept: 60-input, 70-appearance, 71-dms-colors + matugen, 80-keybindings, 91-dms, 92-switcher, OpenHere plugin
(Cursor entry became VS Code), custom.sh (the `clean` command no longer touches the toolbox), starship, fastfetch,
.gitconfig, fonts, Open With, screenshot-notify (Super+Shift+s and Print use DMS + Swappy Edit button; Alt+Print
and Ctrl+Print stay on grimshot), onlyoffice-run (only acts if OnlyOffice is installed), chromium flags hook
(Google sign-in), prime-run, sudoless, LocalSend, firewall rules, i2c udev rule (you pin the monitor yourself),
2 kernels, GRUB font, bgrt boot screen, wallpapers (photos only, you choose), Neovim + dev toolbox + nvim-setup.

Removed: 10-outputs, 90-bar, 90-swayidle, sway/environment, environment.d (qt, wgpu), gtk-theme-follow, Cursor
(VS Code instead), nvidia-settings autostart, btop override (replaced by `ptyxis-e`, a wrapper so DMS can open
"run in terminal" apps in Ptyxis), focus-or-run, nouveau modprobe + dracut files (kernel flags stay; check in VM),
ArtCraft Launcher, microphone 45%, GNOME Software setting, Chromium Intel video decode, DDC auto-pin,
default wallpaper, show-desktop, the full DMS settings file (now a small one: radius 1, fast animations,
idle lock, nothing else; DMS default bar).

Not changed: VM test still has to check nouveau / nova_core; fresh DMS default bar is at the TOP.

## Review of dwm-titus (ChrisTitusTech/dwm-titus), what we took and what we did not

- It is dwm on X11 with its own Quickshell panel; it has no window-preview Alt+Tab / Super+Tab (ours does).
- ISO method: you chose to keep downloading packages during install (kickstart), not its offline image.
- Found in our setup by comparing: `gnome-keyring-pam` was missing (login keyring was never unlocked at login;
  greetd's PAM file asks for it). Added to both kickstarts and apply.sh.
- Checked and fine: firewalld comes with the base group, SELinux stays Enforcing (dwm-titus disables it).
- Done: Starship and Lazygit are now installed only after their SHA-256 matches GitHub's (apply.sh and
  nvim-setup/install-packages.sh). The Claude and Antigravity vendor install scripts stay (your choice; no checksum exists).
- Done: System Doctor DMS plugin (`home/.config/dms/plugins/Doctor`, key `Super+Alt+d`, `dms ipc call doctor toggle`):
  a checklist (Sway, DMS, NVIDIA, nouveau/nova_core, keyring, firewall, SELinux, monitors, disk, kernels), every crash
  (core dump) this boot, failed services, errors in the system and user journals grouped by program (including Sway,
  Quickshell and DMS, which log at normal priority), kernel errors, and DMS's own `dms doctor` report.
  Keys: Up/Down scroll, `c` copies the whole report, `r` re-checks, Esc closes. Read-only.
  Filters built from the logs themselves: Where (User / System / Kernel) and Kind (Sway, DMS, Kernel, System services,
  Apps), biggest group first, with counts. Keys: `u` user, `s` system, `k` kernel, `1`-`9` kind, `a` all; chips are
  clickable too (a mouse click is untested). Tested in the test copy with key presses.
- Still open: the DMS update widget on the bar.
- Finding from the doctor on this machine (to look at with you at the PC): the laptop screen eDP-1 logged about
  2,800 failed page-flips ("Atomic commit failed: Device or resource busy") and 3,100 cursor-plane errors since login,
  mostly in the first 20 minutes; also read errors on the USB stick (sda), failed xdg-document-portal.service.

## Done and checked

- Both kickstarts parse as valid Fedora 44 kickstarts.
- All 108 package names resolve in the Fedora, RPM Fusion and DMS repos.
- `sway -C` passes on this machine; a headless Sway 1.12 loaded the merged config and reloaded it.
- Sway 1.12 + wlroots 0.20 installed on this machine; niri still installed next to it.
- DMS runs on Sway via `exec dms run`; its systemd unit stays tied to niri only (no double start).
- Greeter: `dms-greeter` builds its own Sway config, so `--command sway` is enough.
- Portals: Sway ships `sway-portals.conf` (gtk + wlr + gnome-keyring).

## Built since the first plan (tested headless, not yet in a real Sway session)

- `sway-rpm` repo: https://github.com/musmandev092/sway-rpm (public, GitHub Pages). Weekly Action rebuilds Rawhide
  `sway` + `wlroots` for Fedora 44, signs them with a new key and publishes. First build is live; packages verified
  signed (`rpmkeys --checksig` OK, fingerprint EF93D47772AB894B8232582B49C90DF85566D034). The private key is a GitHub
  secret; a backup is `~/sway-rpm-signing-key.asc` (keep it, do not share it).
- Installer: kickstarts add the repo and install `sway wlroots` from it; the same RPMs are bundled in `install/rpms/`
  as an offline fallback. `apply.sh` does the same on an installed system.
- Switcher plugin (`home/.config/dms/plugins/Switcher`): Alt+Tab = windows of this workspace with previews (hold Alt,
  Tab moves, release switches; quick tap = previous window), Super+Tab = all workspaces with previews, arrows/click/Return
  to pick, Esc cancels. Previews come from `grim -T`, which also works for windows on other workspaces.
- (updated) `Super+/`: searchable shortcut list. Just type to search; Up/Down + Enter or a mouse click runs the shortcut's action; Esc or a click outside closes. Tested: search, Enter-run, Esc, scrolling. Not tested: a real mouse click (the test copy has no mouse); it calls the same function as Enter.
- (old) `Super+/` = `sway-keys`: merges the spin, DMS and your own bindings into one list shown by DMS (98 shortcuts).
- `nvidia-mem-lock.service` removed from the setup (the running machine still has it enabled).

## Still to do

1. Log in to Sway from the login screen and try the keys (see the list in "Key decisions"), the switcher, `Super+/`,
   the DMS bar, both external monitors and the NVIDIA apps.
2. Fix whatever step 1 shows.
3. Optional on this machine: add the sway-rpm repo (`./apply.sh system`) so `dnf upgrade` follows it; disable
   `nvidia-mem-lock.service` if you want it gone now.
4. Download the Fedora 44 Everything netinstall ISO (needs your OK; you said: at the end).
5. Install `lorax` in an `iso` toolbox and run `install/build-iso.sh` (both ISOs).
6. Test the ISO, then copy it to the Ventoy USB (replaces the old niri ISO; needs your OK).
7. Commit the `sway` branch and merge to `main` when you say so.

## Do not

- Do not build the ISO before step 1 and 2 are clean.
- Do not touch the niri session or `main` until Sway is accepted.
- Do not remove niri from this machine yet.
- Do not use passwordless sudo outside the testing window.

## Doctor: Security view (Lynis)
- Doctor plugin has a Security view: `l` runs Lynis without admin (~33 s), `Shift+L` runs with admin via pkexec (UNTESTED), `d` goes back, `1-9` area chips, `a` all, `c` copy.
- Lynis (Fedora package, GPL-3.0) is installed by both kickstarts and apply.sh. Read-only; the script only parses its report in ~/.cache/my_system-doctor.
- Measured here: score 64 (no admin) / 65 (admin), 0 warnings, ~31-39 suggestions, many server-only.
- Decision: the user will apply the security suggestions themselves later; nothing is auto-hardened by the installer.
