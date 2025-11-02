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

## Known Issues and Workarounds

### Device Tab Crash on Linux (Klipper/Fluidd printers)

**Issue:** OrcaSlicer may crash or segfault when clicking the Device tab with Klipper/Fluidd printers on Linux systems.

**Root Causes:**
1. **WebKit Library Version** - OrcaSlicer was built against older webkit2gtk-4.1 library
2. **Windows File Paths** - Config migration from Windows can leave invalid file paths

**Automatic Fixes Applied:**
- ✅ This role patches CMakeLists.txt to use **webkitgtk-6.0** instead of webkit2gtk-4.1 (Arch Linux only)
- ✅ Installs webkitgtk-6.0 package as dependency

**Manual Workaround (if crash persists):**
1. **Fix printer connection** - Add Moonraker port to bypass Fluidd interface:
   ```bash
   # Edit printer config files
   sed -i 's/"print_host": "192.168.1.XXX"/"print_host": "192.168.1.XXX:7125"/' \
       ~/.config/OrcaSlicer/user/default/machine/*.json
   ```
   This connects directly to Moonraker (port 7125) instead of Fluidd, preventing the crash.

2. **Clean Windows file paths** from recent projects:
   ```bash
   # Backup config
   cp ~/.config/OrcaSlicer/OrcaSlicer.conf{,.backup}
   
   # Remove Windows paths (C:\Users\...) from recent_projects section
   # Edit ~/.config/OrcaSlicer/OrcaSlicer.conf manually
   ```

**Limitations with Moonraker workaround:**
- ✅ Can upload G-code files
- ✅ Can start prints remotely  
- ❌ Device tab shows Moonraker API page instead of Fluidd UI
- 💡 Access full Fluidd interface in browser: `http://<printer-ip>`

**Related Issues:**
- Upstream bug: [#10756](https://github.com/SoftFever/OrcaSlicer/issues/10756) - Device tab crash with Klipper
- Related fix: [#7210](https://github.com/SoftFever/OrcaSlicer/issues/7210) - WebKit library upgrade

### NVIDIA + Wayland Graphics Issues

**Issue:** White screen or graphics rendering problems on NVIDIA GPUs with Wayland (driver versions > 555)

**Automatic Fix:**
- ✅ This role automatically detects NVIDIA + Wayland combination
- ✅ Creates a wrapper script with required environment variables
- ✅ Desktop entry configured to use wrapper when needed

**How it works:**
- Detects Wayland session via socket: `/run/user/$UID/wayland-0`
- Checks for NVIDIA kernel module: `lsmod | grep nvidia`
- Verifies driver version > 555: `nvidia-smi`
- If all conditions met, creates `orca-slicer-wrapper.sh` with Mesa/Zink workarounds

**Manual verification:**
```bash
# Check if wrapper exists
ls -l /usr/local/orca-slicer/orca-slicer-wrapper.sh

# Test wrapper
/usr/local/orca-slicer/orca-slicer-wrapper.sh
```

## License

MIT

## Author Information

Created for managing 3D printing workstation setups