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

  # Set up environment to use Wolf's compositor
  export XDG_CURRENT_DESKTOP=openbox
  export XDG_SESSION_TYPE=wayland
  export _JAVA_AWT_WM_NONREPARENTING=1
  export GDK_BACKEND=wayland
  export MOZ_ENABLE_WAYLAND=1
  export QT_QPA_PLATFORM=wayland
  export QT_AUTO_SCREEN_SCALE_FACTOR=1
  export QT_ENABLE_HIGHDPI_SCALING=1
  export GTK_THEME=Arc-Dark:dark
  
  # Use the wayland display provided by Wolf
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  export DISPLAY=""

  gow_log "[Openbox] - Starting desktop environment (connecting to compositor)"

  # Start Openbox + tint2 + pcmanfm using dbus-run-session
  dbus-run-session -- bash -E -c "
    openbox &
    sleep 2
    tint2 &
    pcmanfm --desktop &
    wait
  "
}

# Run launcher if this script is executed directly
launcher
