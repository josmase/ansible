# MJPG-Streamer Role

This role installs and configures MJPG-Streamer for webcam streaming, commonly used with 3D printers.

## Requirements

- Ansible 2.9 or higher
- Linux system with build tools
- USB webcam or compatible camera device

## Role Variables

```yaml
# Default variables (defaults/main.yml)
mjpg_streamer_user: "pi"               # User to run the service as
mjpg_streamer_group: "pi"              # Group to run the service as
mjpg_streamer_install_dir: "/opt/mjpg-streamer"  # Installation directory
mjpg_streamer_device: "/dev/video0"    # Video device path
mjpg_streamer_resolution: "1280x720"   # Stream resolution
mjpg_streamer_fps: "30"                # Frames per second
mjpg_streamer_port: "8080"             # Web server port
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: cameras
  roles:
    - mjpg-streamer
  vars:
    mjpg_streamer_port: "8090"
    mjpg_streamer_resolution: "1920x1080"
```

## License

MIT

## Author Information

Created by josmase