---
# 3D Printing and Modeling Setup Role

This role sets up a workstation for 3D printing and modeling workflows, including:

## 3D Modeling Software
- CAD tools
- Mesh editors
- Design software

## 3D Printing Tools
- **OrcaSlicer** - Advanced 3D printing slicer (built from source)
- Slicing software
- Print management tools
- Firmware tools

## Requirements

- Ansible 2.9 or higher
- Supported distributions: Arch Linux, Debian/Ubuntu

## Role Variables

### Default Variables

Variables are defined in `defaults/main.yml` and can be overridden in inventory or playbook.

#### OrcaSlicer Operation Mode

- `orcaslicer_operation` - Controls what operation to perform
  - `install` (default) - Fresh installation of OrcaSlicer
  - `update` - Update existing OrcaSlicer to latest version
  - `uninstall` - Remove OrcaSlicer installation

#### Installation Paths

- `orcaslicer_install_dir` - Base installation directory (default: `/usr/local/orca-slicer`)
- `orcaslicer_build_dir` - Temporary build directory
- `orcaslicer_build_jobs` - Parallel build jobs (default: 6, to prevent OOM on 32GB systems)

## Dependencies

None. This role is self-contained and does not rely on external roles.

## Example Playbook

```yaml
- hosts: workstations
  become: true
  roles:
    - role: 3d_printing_setup
```

## Tags

Available tags for this role:

### Installation Tags
- `3d-printing` - All 3D printing related installations
- `orcaslicer` - Install OrcaSlicer from source
- `modeling` - 3D modeling software
- `slicing` - Slicing software for 3D printing

### Update Tags
- `3d-printing-update` - Update 3D printing software
- `orcaslicer-update` - Update OrcaSlicer to latest version

### Uninstall Tags
- `orcaslicer-uninstall` - Remove OrcaSlicer installation

### Usage Examples

Install OrcaSlicer (using default operation mode):
```bash
ansible-playbook playbooks/site.yml --tags "3d-printing,orcaslicer" -l archlinux.localdomain
```

Update OrcaSlicer (using tags to select update play):
```bash
ansible-playbook playbooks/site.yml --tags "maintenance" -l archlinux.localdomain
# or more specifically:
ansible-playbook playbooks/maintenance/updates.yml --tags "orcaslicer" -l archlinux.localdomain
```

Uninstall OrcaSlicer (override operation variable):
```bash
ansible-playbook playbooks/site.yml --tags "3d-printing,orcaslicer" -l archlinux.localdomain -e "orcaslicer_operation=uninstall"
```

Force reinstall:
```bash
ansible-playbook playbooks/site.yml --tags "3d-printing,orcaslicer" -l archlinux.localdomain -e "orcaslicer_operation=install"
```

### Notes

- The `orcaslicer_operation` variable controls which tasks run: `install`, `update`, or `uninstall`
- Both installation and update playbooks use the same tags (`3d-printing`, `orcaslicer`)
- The operation is determined by the `orcaslicer_operation` variable set in each playbook
- Default operation is `install` if not specified
- You can override the operation with `-e "orcaslicer_operation=<value>"`

## License

MIT

## Author Information

Created for managing 3D printing workstation setups