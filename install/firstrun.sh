#!/bin/bash
set -u
state="$HOME/.local/state/my_system"
log="$state/firstrun.log"
mkdir -p "$state"
notify() { notify-send -a "my_system" "$@" 2>/dev/null || true; }

for _ in $(seq 120); do
    curl -fsS -o /dev/null --max-time 5 https://fedoraproject.org/ && break
    sleep 5
done
sleep 15

steps="home toolbox nvim"
[ -e "$HOME/Projects/my_system/.lean" ] && steps="home"   # lean build: toolbox and Neovim later, by hand
notify "Setting up your desktop" "Dotfiles and tools ($steps): a few minutes. You can keep working."
if "$HOME/Projects/my_system/apply.sh" $steps > "$log" 2>&1; then
    touch "$state/firstrun.done"
    notify "Your desktop is ready" "Everything is set up. Log: $log"
else
    notify -u critical "Setup did not finish" "See $log. It will retry at the next login, or run ~/Projects/my_system/apply.sh"
fi
