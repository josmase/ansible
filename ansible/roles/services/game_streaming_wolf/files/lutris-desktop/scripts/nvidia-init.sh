#!/bin/bash

set -e

source /opt/gow/bash-lib/utils.sh

if [ -d /usr/nvidia ]; then
    gow_log "Nvidia driver volume detected"
    ldconfig

    if [ -d /usr/nvidia/share/vulkan/icd.d ]; then
        gow_log "[nvidia] Add Vulkan ICD"
        mkdir -p /etc/vulkan/icd.d/
        cp /usr/nvidia/share/vulkan/icd.d/* /etc/vulkan/icd.d/
    fi

    if [ -d /usr/nvidia/share/egl/egl_external_platform.d ]; then
        gow_log "[nvidia] Add EGL external platform"
        mkdir -p /usr/share/egl/egl_external_platform.d/
        cp /usr/nvidia/share/egl/egl_external_platform.d/* /usr/share/egl/egl_external_platform.d/
    fi

    if [ -d /usr/nvidia/share/glvnd/egl_vendor.d ]; then
        gow_log "[nvidia] Add egl-vendor"
        mkdir -p /usr/share/glvnd/egl_vendor.d/
        cp /usr/nvidia/share/glvnd/egl_vendor.d/* /usr/share/glvnd/egl_vendor.d/
    fi

    if [ -d /usr/nvidia/lib/gbm ]; then
        gow_log "[nvidia] Add gbm backend"
        mkdir -p /usr/lib/x86_64-linux-gnu/gbm/
        cp /usr/nvidia/lib/gbm/* /usr/lib/x86_64-linux-gnu/gbm/
    fi

    ldconfig
fi
