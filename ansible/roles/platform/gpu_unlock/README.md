# GPU Unlock Role

This host-level role manages the early-boot GPU unlock capability for an
Eligible GPU. It is independent of Kubernetes, container runtimes, Tdarr, and
NVIDIA driver management.

Set `gpu_unlock_enabled: true` to apply it. The role reads PCI IDs from sysfs,
selects every upstream-allowlisted NVIDIA device, and configures the GPU unlock
target set as `all`. An Ineligible host is a successful no-op. Set the opt-in
to `false` to remove role-managed packages, GRUB token, and revision record.

The full `gpu_unlock_revision` SHA is Renovate-managed. A changed revision is
rebuilt and reinstalled even where the Debian package version is unchanged.

Only Debian/Ubuntu hosts using GRUB are supported. The host must already have
`deb-src`, matching kernel headers, and an NVIDIA driver. The role rejects
Secure Boot, does not change APT sources or drivers, and never reboots. It
reports `gpu_unlock_reboot_required: true` when boot-time state changes.

After an operator-coordinated reboot, use the explicit verification entrypoint:

```yaml
- ansible.builtin.import_role:
    name: platform/gpu_unlock
    tasks_from: verify
```

That verifies the loaded module and current-boot kernel messages. Performance
and actual hardware unlock remain manual acceptance checks.
