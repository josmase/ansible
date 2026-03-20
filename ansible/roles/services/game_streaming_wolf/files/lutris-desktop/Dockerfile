ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/lutris:edge

FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    matchbox-window-manager \
    lxpanel \
    pcmanfm \
    dbus-x11 \
    papirus-icon-theme \
    arc-theme \
    && rm -rf /var/lib/apt/lists/*

# Override nvidia init to handle read-only EGL directories
COPY scripts/nvidia-init.sh /etc/cont-init.d/30-nvidia.sh

COPY scripts/startup.sh /opt/gow/startup-app.sh
COPY scripts/launch-comp.sh /opt/gow/launch-comp.sh

RUN chmod 777 /opt/gow/startup-app.sh /opt/gow/launch-comp.sh /etc/cont-init.d/30-nvidia.sh
