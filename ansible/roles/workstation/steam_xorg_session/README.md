# Steam Xorg Session Role

Provision a minimal X11 session dedicated to Steam/Proton gaming. The role installs the required Xorg packages, drops a launcher script, and registers a desktop session that can be selected from the display manager.

## Requirements

- A display manager such as GDM, SDDM, or LightDM.

## Role Variables

All variables live in `defaults/main.yml`.

- `steam_xorg_session_packages`: Per-OS package list required to run the session (includes Openbox for the default setup).
- `steam_xorg_session_gamescope_packages`: Optional package list installed when enabling gamescope support.
- `steam_xorg_session_steam_package`: Map of Steam package names per OS family.
- `steam_xorg_session_script_path`: Absolute path to the launcher script.
- `steam_xorg_session_desktop_entry_path`: Desktop entry location.
- `steam_xorg_session_name`: Name shown in the login session selector.
- `steam_xorg_session_comment`: Description displayed by the greeter.
- `steam_xorg_session_steam_binary`: Steam executable path.
- `steam_xorg_session_environment`: Optional map of environment variables exported before Steam launches.
- `steam_xorg_session_autostart_delay`: Seconds to wait before launching Steam.
- `steam_xorg_session_use_gamescope`: Toggle to replace the Openbox-based session with gamescope's `--steam` mode.

## Example Playbook

```yaml
- name: Configure dedicated Steam Xorg session
  hosts: gaming_workstations
  become: true
  roles:
    - workstation/steam_xorg_session
```

## Notes

- The desktop entry is written to `/usr/share/xsessions`, which is consumed by most display managers.
- Steam is installed via the package specified in `steam_xorg_session_steam_package`.
- Override `steam_xorg_session_environment` to set Proton/NVIDIA workarounds (for example `__GLX_VENDOR_LIBRARY_NAME`).
- Set `steam_xorg_session_use_gamescope: true` if you want to run Steam through gamescope's fullscreen compositor. The default Openbox-based session is more conservative and avoids gamescope's GPU/Xwayland requirements.
