#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

function launcher() {
    if [ -n "$RUN_SWAY" ]; then
        gow_log "[Sway] - Starting desktop environment"

        export XDG_CURRENT_DESKTOP=sway
        export XDG_SESSION_DESKTOP=sway
        export XDG_SESSION_TYPE=wayland
        export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
        
        mkdir -p "$HOME/.config/sway"
        mkdir -p "$HOME/.config/waybar"
        
        cp /etc/sway/config-template "$HOME/.config/sway/config"
        cp /opt/gow/waybar/config.json "$HOME/.config/waybar/config.json" 2>/dev/null || true
        
        dbus-run-session -- sway --unsupported-gpu
    else
        gow_log "[Desktop] - Starting with X11"
        export DISPLAY=:0
        export GDK_BACKEND=x11
        
        dbus-run-session -- bash -c "
            Xwayland :0 &
            sleep 2
            openbox-session &
            sleep 1
            tint2 &
            pcmanfm --desktop &
            wait
        "
    fi
}

launcher
