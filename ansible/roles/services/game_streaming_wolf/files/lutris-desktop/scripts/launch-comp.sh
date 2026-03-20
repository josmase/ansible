#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

function launcher() {
    export DISPLAY=:0
    export GDK_BACKEND=x11
    export GTK_THEME=Arc-Dark:dark
    
    mkdir -p "$HOME/.config"
    
    gow_log "[X11 Desktop] - Starting desktop environment"
    
    dbus-run-session -- bash -c "
        matchbox-window-manager &
        sleep 1
        lxpanel &
        pcmanfm --desktop &
        wait
    "
}

launcher
