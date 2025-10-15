# Obico Server Role

This role installs and configures the Obico server (formerly The Spaghetti Detective) for 3D printer monitoring and AI-powered failure detection.

## Requirements

- Ansible 2.9 or higher
- Docker and Docker Compose (handled by docker_setup role)
- Git for repository cloning

## Role Variables

```yaml
# Default variables (defaults/main.yml)
obico_repo_dir: "/opt/obico-server"    # Directory for Obico server installation
obico_version: "release"               # Git branch/tag to use
```

## Dependencies

- docker_setup (must be applied before this role)

## Example Playbook

```yaml
- hosts: printer_monitoring
  roles:
    - docker_setup
    - obico-server
  vars:
    obico_repo_dir: "/srv/obico"
```

## License

MIT

## Author Information

Created by josmase