ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/lutris:edge

FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openbox \
    tint2 \
    obconf \
    lxappearance \
    pcmanfm \
    dbus-x11 \
    papirus-icon-theme \
    arc-theme \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Override nvidia init to handle read-only EGL directories
COPY scripts/nvidia-init.sh /etc/cont-init.d/30-nvidia.sh

COPY scripts/startup.sh /opt/gow/startup-app.sh
COPY scripts/launch-comp.sh /opt/gow/launch-comp.sh
COPY scripts/start-desktop /opt/gow/start-desktop
COPY configs/openbox /opt/gow/openbox
COPY configs/tint2 /opt/gow/tint2

RUN chmod 777 /opt/gow/startup-app.sh /opt/gow/launch-comp.sh /opt/gow/start-desktop /etc/cont-init.d/30-nvidia.sh

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix
