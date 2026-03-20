#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

function launcher() {
  export GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
  export GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
  export GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}

  if [ -n "$RUN_GAMESCOPE" ]; then
    gow_log "[Gamescope] - Starting: \`$@`"

    GAMESCOPE_MODE=${GAMESCOPE_MODE:-"-b"}
    /usr/games/gamescope "${GAMESCOPE_MODE}" -W "${GAMESCOPE_WIDTH}" -H "${GAMESCOPE_HEIGHT}" -r "${GAMESCOPE_REFRESH}" -- "$@"
  elif [ -n "$RUN_SWAY" ]; then
    gow_log "[Sway + Openbox] - Starting desktop environment"

    export SWAYSOCK=${XDG_RUNTIME_DIR}/sway.socket
    export SWAY_STOP_ON_APP_EXIT=${SWAY_STOP_ON_APP_EXIT:-"no"}
    export XDG_CURRENT_DESKTOP=sway
    export XDG_SESSION_DESKTOP=sway
    export XDG_SESSION_TYPE=wayland

    # Setup default config on first run
    if [ ! -d "$HOME/.config/openbox" ]; then
      mkdir -p $HOME/.config/openbox $HOME/.config/tint2
      cp -r /opt/gow/openbox/* $HOME/.config/openbox/
      cp -r /opt/gow/tint2/* $HOME/.config/tint2/
      mkdir -p ~/Desktop ~/Documents ~/Downloads ~/Games ~/Pictures
    fi

    # Sway config for resolution
    mkdir -p $HOME/.config/sway/
    cp /cfg/sway/config $HOME/.config/sway/config
    echo "output * resolution ${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT} position 0,0" >> $HOME/.config/sway/config

    # Start sway with Openbox session
    echo -n "workspace main; exec /opt/gow/start-desktop" >> $HOME/.config/sway/config

    dbus-run-session -- sway --unsupported-gpu
  else
    gow_log "[exec] Starting: $@"

    exec $@
  fi
}
