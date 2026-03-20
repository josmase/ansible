# Diablo 2 Resurrected Lutris Setup

Sets up multiple Lutris Battle.net instances with shared Diablo II Resurrected game files via symlinks.

## Structure

- `battlenet1`: Primary installation (install Diablo 2 here via Lutris GUI)
- `battlenet2`: Symlinks to battlenet1's Diablo II folder
- `battlenet3`: Symlinks to battlenet1's Diablo II folder

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `lutris_base_path` | Base directory for Lutris games | OS-dependent |

### OS-specific Default Paths

| OS Family | Default Path |
|-----------|--------------|
| Debian | `/media/ubuntu/Games` |
| Archlinux | `~/.lutris/games` |

Override in `inventory/group_vars/all/main.yml`:

```yaml
lutris_base_path:
  Debian: "/custom/path"
  Archlinux: "/custom/path"
```

## Usage

### 1. Install Lutris and setup directories

```bash
ansible-playbook playbooks/setup/diablo2_lutris.yml --tags lutris,setup
```

### 2. Install Diablo 2 through Lutris GUI

1. Open Lutris
2. Select "Battle.net 1" runner
3. Install Diablo 2 Resurrected

### 3. Create symlinks

```bash
ansible-playbook playbooks/setup/diablo2_lutris.yml --tags symlinks
```

### 4. Configure Lutris instances

```bash
ansible-playbook playbooks/setup/diablo2_lutris.yml --tags configure
```

### Full Run

```bash
# Install and setup (before installing game)
ansible-playbook playbooks/setup/diablo2_lutris.yml --tags lutris,setup

# After installing Diablo 2 on battlenet1 via GUI
ansible-playbook playbooks/setup/diablo2_lutris.yml --tags symlinks,configure
```

## Requirements

### Arch Linux
- `yay` or `paru` AUR helper (for Lutris)
- Wine and dependencies

### Debian/Ubuntu
- Lutris repository
- Wine HQ repository

## Directory Structure

```
{{ lutris_base_path }}/
├── battlenet1/
│   ├── battlenet1.yml
│   └── drive_c/
│       └── Program Files (x86)/
│           └── Diablo II Resurrected/  <- Install game here
├── battlenet2/
│   ├── battlenet2.yml
│   └── drive_c/
│       └── Program Files (x86)/
│           └── Diablo II Resurrected/  <- Symlink to battlenet1
└── battlenet3/
    ├── battlenet3.yml
    └── drive_c/
        └── Program Files (x86)/
            └── Diablo II Resurrected/  <- Symlink to battlenet1
```

## Notes

- The symlink task will fail if `battlenet1/.../Diablo II Resurrected` doesn't exist
- Each instance has its own Wine prefix for Battle.net client
- Game files are shared via symlinks to save disk space
