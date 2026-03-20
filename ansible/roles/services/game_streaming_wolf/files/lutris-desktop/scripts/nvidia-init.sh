#!/usr/bin/env bash
set -e

gow_log "**** Configure nvidia for Desktop ****"

if [ -f /usr/nvidia/bin/nvidia-smi ]; then
    gow_log "Nvidia driver volume detected"
    
    # Only copy EGL files if the directory is writable
    if [ -w /usr/share/egl/egl_external_platform.d/ ]; then
        gow_log "[nvidia] Add EGL external platform"
        cp /usr/nvidia/share/egl/egl_external_platform.d/* /usr/share/egl/egl_external_platform.d/
    else
        gow_log "[nvidia] EGL directory is read-only, skipping"
    fi
    
    if [ -w /usr/share/glvnd/egl_vendor.d/ ]; then
        gow_log "[nvidia] Add egl-vendor"
        cp /usr/nvidia/share/glvnd/egl_vendor.d/* /usr/share/glvnd/egl_vendor.d/
    else
        gow_log "[nvidia] EGL vendor directory is read-only, skipping"
    fi
    
    # Add Vulkan ICD if available
    if [ -f /usr/nvidia/share/vulkan/icd.d/nvidia_icd.json ]; then
        mkdir -p /etc/vulkan/icd.d
        cp /usr/nvidia/share/vulkan/icd.d/nvidia_icd.json /etc/vulkan/icd.d/
        gow_log "[nvidia] Added Vulkan ICD"
    fi
    
    # Update library cache so applications can find NVIDIA libraries
    ldconfig
    gow_log "[nvidia] Updated library cache"
    
    gow_log "DONE"
else
    gow_log "Nvidia driver volume not present, skipping"
fi
