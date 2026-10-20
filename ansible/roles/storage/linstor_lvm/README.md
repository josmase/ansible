# LINSTOR LVM

Creates an LVM thin pool only after matching one disk by exact serial and
size, proving it is not the root disk or mounted, and receiving an exact
per-host erase confirmation. It never wipes an unexpected signature.

The role also attaches an LVM metadata profile to the thin pool. It extends
the pool by 5% when data usage reaches 75%, using only free space deliberately
retained in the volume group. Extra PVs are preserved and the role prohibits
pool shrinking.

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

The final workers use the separate guarded playbook
`ansible/playbooks/setup/linstor-final-expand.yml`. It adds a new PV with two
2 GiB metadata areas (4 GiB total reserved on the expansion disk), checks both
copies before setting `metadataignore` on the original PV, requires at least
16 MiB free VG metadata, and grows the existing pool without shrinking. It
runs one node at a time and refuses mutation until the isolated rehearsal,
external backups, and exact `EXPAND:<inventory-host>:<serial>` confirmation
are supplied.

Configured thin-pool sizes are minimums. Reruns preserve larger pools created
by automatic extension and never shrink them. The expansion playbook also
accepts active LVM mappings on an already verified expansion PV; the empty
disk guard still applies before first initialization. Host monitoring is
enabled persistently through `lvm2-monitor.service`, with a profile visible
in both host and satellite namespaces.

Apply the Flux-managed `host-lvm-profile` satellite configuration before
running the expansion playbook. The playbook labels each prepared worker
`storage.josmase.io/lvm-profile-ready=true`, waits for a ready satellite with
the read-only host profile mount, and checks replica health before the next
worker. This stages satellite pod rollouts serially rather than updating all
worker satellites at once.
