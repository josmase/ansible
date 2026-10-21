# RustFS

Deploys a digest-pinned RustFS S3 endpoint on mergerfs. The systemd unit is
bound to the mergerfs mount so Docker cannot write below an absent mount.
Credentials must come from encrypted inventory variables.

The role preserves the existing `linstor-backups` bucket and credentials, and
also provisions `linstor-backups-v2` with a separate bucket-scoped user and
policy. The v2 user credentials must be stored as encrypted
`rustfs_backup_v2_access_key` and `rustfs_backup_v2_secret_key` variables; never
reuse the legacy key. The role requires at least 1 TiB (1,099,511,627,776
bytes) free on the live mergerfs mount before applying configuration.

## Live protection capacity

A restricted DynamicUser systemd service publishes `__protection/capacity.json` in the dedicated v2 bucket every five minutes. It verifies the required mergerfs mount and reports available bytes and a timestamp. Systemd supplies only the v2 bucket credentials through `LoadCredential`; no root S3 identity is used. The protection gate must reject missing or stale reports and subtract the measured additional retained-backup forecast before applying the absolute free-space floor. This report is a monitoring object, outside LINSTOR backup retention.
