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

- `3d-printing` - All 3D printing related installations
- `modeling` - 3D modeling software
- `slicing` - Slicing software for 3D printing

## License

MIT

## Author Information

Created for managing 3D printing workstation setups