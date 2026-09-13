# LINSTOR LVM

Creates an LVM thin pool only after matching one disk by exact serial and
size, proving it is not the root disk or mounted, and receiving an exact
per-host erase confirmation. It never wipes an unexpected signature.

The role also attaches an LVM metadata profile to the thin pool. By default,
LVM extends the pool by 20% when data usage reaches 80%, using only the free
space deliberately retained in the volume group.

For a permanent 750 GiB worker disk, override the defaults with:

```yaml
linstor_lvm_expected_serial: linstor-data-205
linstor_lvm_expected_size_bytes: 805306368000
linstor_lvm_vg_name: linstor_vg
linstor_lvm_thinpool_name: linstor_thin
linstor_lvm_thinpool_size: 680g
linstor_lvm_thinpool_metadata_size: 4g
```

Initialization still requires `linstor_lvm_initialize=true` and the exact
`ERASE:<inventory-host>:<serial>` confirmation at execution time.
