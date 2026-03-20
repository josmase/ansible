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
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=777 scripts/startup.sh /opt/gow/startup-app.sh
COPY --chmod=777 scripts/launch-comp.sh /opt/gow/launch-comp.sh
COPY --chmod=777 scripts/start-desktop /opt/gow/start-desktop
COPY configs/openbox /opt/gow/openbox
COPY configs/tint2 /opt/gow/tint2

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix
