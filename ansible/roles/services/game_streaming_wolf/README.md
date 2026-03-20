# Wolf Game Streaming Role

Sets up Wolf game streaming server with Tailscale and Lutris support using the [official Nvidia manual install method](https://games-on-whales.github.io/wolf/stable/user/quickstart.html).

## Overview

This role automates the installation and configuration of:
- Wolf game streaming server (Moonlight compatible)
- Tailscale VPN for secure remote access
- Lutris game manager
- Full desktop environment (Openbox + tint2) with Lutris in menu
- Nvidia driver volume for containerized GPU access
- Virtual input devices (uinput/uhid) for gamepad support

## Requirements

- Ubuntu/Debian system
- Docker installed and running
- Nvidia GPU with drivers version >= 530.30.02
- `nvidia-drm` kernel module loaded with `modeset=1` (see below)
- Internet access for downloading images and packages

## Prerequisites

### Enable nvidia-drm modeset

Wolf requires `nvidia-drm` to be loaded with `modeset=1`:

```bash
# Load module with modeset
sudo modprobe nvidia_drm modeset=1

# Make persistent across reboots
echo 'options nvidia_drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf
sudo update-initramfs -u
```

## Role Variables

All variables are defined in `defaults/main.yml` with sensible defaults.

### Key Variables

```yaml
# Enable/disable components
wolf_enabled: true
wolf_tailscale_enabled: true
wolf_lutris_enabled: true
wolf_nvidia_enabled: true
wolf_virtual_devices_enabled: true

# Wolf configuration
wolf_hostname: "game-stream"
wolf_network_mode: "host"
wolf_http_port: 47989

# Tailscale configuration
wolf_tailscale_auth_key: ""  # Optional for unattended installation

# Nvidia configuration
wolf_nvidia_driver_volume: "nvidia-driver-vol"
wolf_nvidia_driver_image: "gow/nvidia-driver:latest"

# Compositor configuration
wolf_compositor: "sway"  # Options: sway, gamescope
wolf_gamescope_width: 1920
wolf_gamescope_height: 1080
wolf_gamescope_refresh: 60

# Wolf apps configuration
wolf_lutris_app_enabled: true
wolf_lutris_image: "ghcr.io/games-on-whales/lutris:edge"

# Desktop configuration (Openbox + tint2)
wolf_desktop_enabled: true
wolf_desktop_image: "lutris-desktop:local"
```

## Usage

### Basic Playbook

```yaml
- hosts: game_streaming_hosts
  become: true
  roles:
    - role: services/game_streaming_wolf
```

### With Custom Variables

```yaml
- hosts: game_streaming_hosts
  become: true
  vars:
    wolf_hostname: "my-game-server"
    wolf_tailscale_auth_key: "tskey-auth-xxxxx"
    wolf_nvidia_driver_volume: "my-nvidia-vol"
  roles:
    - role: services/game_streaming_wolf
```

## Moonlight Pairing

After deployment:
1. Open Moonlight on your client device
2. Add your server IP address
3. Enter the PIN shown in Moonlight at: `http://<server-ip>:47989/pin/`

## Lutris App Configuration

The role automatically configures a Lutris app in Wolf that can be streamed via Moonlight.

### Compositor Options

The Lutris app supports different window managers:

- **Sway** (default): A tiling Wayland compositor
- **Gamescope**: Valve's compositor optimized for gaming

Configure via `wolf_compositor` variable:
```yaml
wolf_compositor: "sway"       # Tiling window manager (default, works well)
wolf_compositor: "gamescope"  # Valve's gaming compositor
```

### Gamescope Settings

When using Gamescope, configure resolution and refresh rate:
```yaml
wolf_gamescope_width: 1920
wolf_gamescope_height: 1080
wolf_gamescope_refresh: 60
```

### Lutris App Variables

```yaml
wolf_lutris_app_enabled: true  # Enable/disable the Lutris app in Wolf
wolf_lutris_image: "ghcr.io/games-on-whales/lutris:edge"  # Lutris Docker image
wolf_lutris_base_path: "/home/user/Games/Lutris"  # Games directory on host
```

## Desktop App Configuration

The role includes a full desktop environment option with Openbox + tint2, providing a non-tiling window manager experience with Lutris available in the application menu.

### Desktop Variables

```yaml
wolf_desktop_enabled: true  # Enable/disable the Desktop app
wolf_desktop_image: "lutris-desktop:local"  # Custom desktop image (built on target)
```

### Desktop Features

- **Openbox**: Floating window manager
- **tint2**: Taskbar with system tray and app launcher
- **PCManFM**: File manager with desktop icons
- **Lutris**: Available in the Openbox menu (not auto-started)

### How It Works

1. The role builds a custom Docker image based on `lutris:edge`
2. Openbox + tint2 packages are installed on top
3. Wolf runs the desktop using Sway as the Wayland compositor
4. XWayland bridges X11 apps to the Wayland session
5. Openbox + tint2 provides a familiar desktop experience

### Resetting Desktop State

If the desktop has issues, clear cached state:
```bash
docker volume rm -f lutris
rm -rf /etc/wolf/profile-data/user/WolfDesktop
docker restart wolf
```

## Port Information

When not using host network mode:
- HTTP: 47989/tcp
- HTTPS: 47984/tcp
- Control: 47999/udp
- RTSP: 48010/tcp
- Video: 48100/udp
- Audio: 48200/udp

## Troubleshooting

### Black Screen with Cursor
Wolf is downloading required images. Check logs:
```bash
docker logs wolf
```

### Nvidia Devices Missing
Ensure nvidia-drm module is loaded with modeset=1:
```bash
cat /sys/module/nvidia_drm/parameters/modeset
# Should output: Y
```

### Virtual Devices Not Working
Check udev rules are loaded:
```bash
udevadm control --reload-rules && udevadm trigger
```

### Resetting Lutris State
If Lutris has issues, clear cached state:
```bash
docker volume rm -f lutris
rm -rf /etc/wolf/profile-data/user/WolfLutris
docker restart wolf
```

## Dependencies

None. This role is self-contained.

## License

MIT

## Author

Ansible
