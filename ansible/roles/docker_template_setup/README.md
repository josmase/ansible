# Docker Template Setup Role

This role manages Docker Compose templates and container deployments for various services.

## Requirements

- Ansible 2.9 or higher
- Docker and Docker Compose (handled by docker_setup role)

## Role Variables

```yaml
# From docker_setup role
docker_compose_dir: /opt/docker           # Directory for docker-compose files
docker_script_dir: /opt/docker/scripts    # Directory for maintenance scripts

# Role-specific variables
docker_templates:                         # List of templates to deploy
  - pihole                               # DNS and ad blocking
  - unifi                                # UniFi Network Application
  - plex                                 # Plex Media Server
  # Add other templates as needed

main_username: "user"                     # Owner of deployed files
main_groupname: "group"                   # Group for deployed files
```

## Dependencies

- docker_setup (must be applied before this role)

## Available Templates

### Media Services
- plex.yml - Plex Media Server
- emby.yml - Emby Media Server
- jellyfin.yml - Jellyfin Media Server
- tdarr.yml - Media transcoding
- tubearchivist.yml - YouTube archive

### Network Services
- pihole.yml - DNS and ad blocking
- unifi.yml - UniFi Network Application
- wireguard.yml - VPN server
- swag.yml - Reverse proxy and SSL

### File Sharing
- smb.yml - Samba file sharing
- nfs.yml - NFS server
- ftp.yml - FTP server
- copyparty.yml - Web-based file sharing

### Monitoring
- grafana.yml - Metrics visualization
- influxdb.yml - Time series database
- telegraf.yml - Metrics collection
- monitoring.yml - System monitoring suite

### Download Management
- transmission.yml - BitTorrent client
- fileflow.yml - File management
- midarr.yml - Media requests
- ombi.yml - Media requests

## Example Playbook

```yaml
- hosts: docker_hosts
  roles:
    - docker_setup
    - docker_template_setup
  vars:
    docker_templates:
      - pihole
      - unifi
      - plex
```

## License

MIT

## Author Information

Created by josmase