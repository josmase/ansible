# Ansible Infrastructure Management

This repository contains Ansible playbooks and roles for managing various infrastructure components including:
- Development machines
- Media servers
- Network storage
- 3D printer monitoring
- System maintenance

## Quick Start

### Prerequisites

1. Install Ansible:
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install ansible

# Arch Linux
sudo pacman -S ansible
```

2. Clone this repository:
```bash
git clone https://github.com/josmase/ansible.git
cd ansible
```

3. Set up your local environment:
```bash
# Initialize local development environment
ansible-playbook playbooks/local_setup.yml

# If using vault-encrypted variables
ansible-playbook playbooks/local_setup.yml --ask-vault-pass
```

## Common Use Cases

### 1. Setting Up a Development Machine

```bash
# Full development environment setup
ansible-playbook playbooks/site.yml --tags "setup" --limit "dev_machines" -K

# Specific components
ansible-playbook playbooks/site.yml --tags "setup,docker" --limit "dev_machines" -K
```

This will:
- Install development tools and utilities
- Configure Git
- Set up Docker environment
- Install required packages
- Configure system preferences

### 2. Managing Media Server

```bash
# Initial media server setup
ansible-playbook playbooks/site.yml --tags "setup,media" --limit "media_server"

# Deploy or update container services
ansible-playbook playbooks/services/containers.yml --limit "media_server"
```

### 3. Storage System Management

```bash
# Set up storage system
ansible-playbook playbooks/setup/storage.yml --limit "storage"

# Add new drive
ansible-playbook playbooks/setup/storage.yml --limit "storage" --tags "drives" \
  -e "new_drive=/dev/sdb"
```

#### Adding a New Drive

1. Identify the drive:
```bash
ls -la /dev/disk/by-id
```

2. For VM setup:
```bash
qm set $VM_ID -scsi$DRIVE_NUMBER /dev/disks/by-id/$DRIVE_ID
```

3. Format with LUKS-encrypted XFS:
```bash
DRIVE="drive_name"
sudo sgdisk -n 1:0:0 /dev/$DRIVE
sudo cryptsetup luksFormat /dev/${DRIVE}1 --key-file ./keyfile
sudo cryptsetup luksOpen /dev/${DRIVE}1 ${DRIVE}1 --key-file ./keyfile
sudo mkfs.xfs /dev/mapper/${DRIVE}1
```

### 4. System Maintenance

```bash
# Update all systems
ansible-playbook playbooks/maintenance/updates.yml --limit "all"

# Controlled reboot of specific systems
ansible-playbook playbooks/maintenance/reboot.yml --limit "k3s_cluster"
```

### 5. 3D Printer Setup

```bash
# Set up complete printer monitoring
ansible-playbook playbooks/setup/printer.yml --limit "printer_support"

# Update only Obico server
ansible-playbook playbooks/setup/printer.yml --limit "printer_monitors"
```

## Project Structure

```
ansible/
├── playbooks/           # All playbooks organized by function
│   ├── site.yml        # Main entry point
│   ├── setup/          # Initial setup playbooks
│   └── maintenance/    # System maintenance
├── roles/              # Reusable roles grouped by domain
│   ├── core/
│   ├── container/
│   ├── platform/
│   ├── storage/
│   ├── services/
│   ├── workstation/
│   └── validation/
├── inventory/group_vars/ # Group variables
├── inventory/host_vars/  # Host-specific variables
└── collections/       # Collection requirements
```

## Tags

Common tags for selective execution:
- `setup`: Initial system setup
- `maintenance`: System maintenance tasks
- `services`: Service management
- `docker`: Docker-related tasks
- `storage`: Storage management
- `security`: Security-related tasks
- `backup`: Backup operations

## Inventory Groups

- `dev_machines`: Development workstations
- `media_server`: Media streaming servers
- `storage`: Storage servers
- `printer_support`: 3D printer monitoring
- `k3s_cluster`: Kubernetes nodes

## Best Practices

1. Always use `--check` first for potentially destructive operations
2. Use tags to run specific parts of playbooks
3. Keep sensitive data in vault-encrypted files
4. Test changes in staging when possible
5. Use limit to target specific hosts

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT

## Author

Created and maintained by josmase