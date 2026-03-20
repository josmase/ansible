#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

function launcher() {
  # Setup default config on first run
  if [ ! -d "$HOME/.config/openbox" ]; then
    mkdir -p $HOME/.config/openbox $HOME/.config/tint2
    cp -r /opt/gow/openbox/* $HOME/.config/openbox/
    cp -r /opt/gow/tint2/* $HOME/.config/tint2/
    mkdir -p ~/Desktop ~/Documents ~/Downloads ~/Games ~/Pictures
    chmod 755 ~/Desktop ~/Documents ~/Downloads ~/Games ~/Pictures
  fi

  export DESKTOP_SESSION=openbox
  export XDG_CURRENT_DESKTOP=openbox
  export XDG_SESSION_TYPE="x11"
  export _JAVA_AWT_WM_NONREPARENTING=1
  export GDK_BACKEND=x11
  export MOZ_ENABLE_WAYLAND=0
  export QT_QPA_PLATFORM="xcb"
  export QT_AUTO_SCREEN_SCALE_FACTOR=1
  export QT_ENABLE_HIGHDPI_SCALING=1
  export DISPLAY=:0
  export GTK_THEME=Arc-Dark:dark

  export REAL_WAYLAND_DISPLAY=$WAYLAND_DISPLAY
  unset WAYLAND_DISPLAY

  gow_log "[Openbox] - Starting desktop environment"

  # Start Xwayland + Openbox + tint2 with dbus-run-session
  dbus-run-session -- bash -E -c "WAYLAND_DISPLAY=\$REAL_WAYLAND_DISPLAY Xwayland :0 & sleep 2 && openbox-session & sleep 1 && tint2 & pcmanfm --desktop & wait"
}

# Run launcher if this script is executed directly
launcher
