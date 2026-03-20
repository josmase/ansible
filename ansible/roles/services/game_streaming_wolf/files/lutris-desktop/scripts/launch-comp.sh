#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

function launcher() {
  export GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
  export GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
  export GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}

  if [ -n "$RUN_GAMESCOPE" ]; then
    gow_log "[Gamescope] - Starting desktop session"
    export DISPLAY=:0
    export GDK_BACKEND=x11
    export GTK_THEME=Arc-Dark:dark
    
    dbus-run-session -- bash -c "
      Xwayland :0 &
      sleep 3
      openbox-session &
      sleep 2
      lxpanel &
      pcmanfm --desktop &
      wait
    "
  elif [ -n "$RUN_SWAY" ]; then
    gow_log "[Sway] - Starting desktop session"
    
    export SWAYSOCK=${XDG_RUNTIME_DIR}/sway.socket
    export SWAY_STOP_ON_APP_EXIT=${SWAY_STOP_ON_APP_EXIT:-"yes"}
    export XDG_CURRENT_DESKTOP=sway
    export XDG_SESSION_DESKTOP=sway
    export XDG_SESSION_TYPE=wayland
    
    mkdir -p $HOME/.config/sway/
    cp /cfg/sway/config $HOME/.config/sway/config
    echo "output * resolution ${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT} position 0,0" >> $HOME/.config/sway/config
    
    dbus-run-session -- sway --unsupported-gpu
  else
    gow_log "[exec] Starting: $@"
    exec $@
  fi
}

launcher
