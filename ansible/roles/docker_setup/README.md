# Docker Installation Role

This role handles the installation and configuration of Docker on target systems.

## Requirements

- Ansible 2.9 or higher
- A supported operating system (Debian/Ubuntu or Arch Linux)

## Role Variables

## Role Variables

All variables have defaults but can be overridden as needed.

### Base Configuration
```yaml
docker_user: "{{ ansible_user }}"   # User who owns Docker files and is in docker group
docker_group: "docker"              # Docker group name
docker_setup_enabled: true          # Enable/disable Docker setup tasks
```

### Directory Paths
```yaml
docker_compose_dir: "/opt/docker/compose"    # Docker compose files location
docker_script_dir: "/opt/docker/scripts"     # Helper scripts location
docker_data_dir: "/opt/docker/data"         # Application data directory
docker_storage_dir: "/opt/docker/storage"    # Storage for container data
```

### Features and Templates
```yaml
docker_script_templates:             # List of script templates to install
  - "common"
  - "maintenance"
  - "staleFileHandleHandler"
  - "start"
  - "stop"
  - "update"

docker_maintenance_timer_calendar: ""  # Systemd timer schedule for maintenance
docker_nfs_enabled: false             # Enable NFS support for Docker volumes
```

## Dependencies

None.

## Example Playbooks

### Basic Docker Setup
```yaml
- hosts: docker_hosts
  vars:
    docker_setup_enabled: true
    docker_nfs_enabled: false
  roles:
    - docker_setup
```

### Full Setup with NFS and Maintenance
```yaml
- hosts: docker_hosts
  vars:
    docker_setup_enabled: true
    docker_nfs_enabled: true
    docker_maintenance_timer_calendar: "0 3 * * *"  # Run at 3 AM daily
  roles:
    - docker_setup
```

```yaml
- hosts: docker_hosts
  roles:
    - role: docker_setup
      vars:
        docker_templates:
          - nfs
          - home-assistant
```

## Tags

- `docker` - All docker-related tasks
- `timers` - Timer configuration tasks
- `scripts` - Script installation tasks

## Author

Jonas Lundberg