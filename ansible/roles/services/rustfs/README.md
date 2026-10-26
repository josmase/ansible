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

## GitLab CI and OpenTofu storage

Production enables `rustfs_gitlab_storage_enabled` to preserve the recovered
`gitlab-terraform-state` backend and the `gitlab-artifacts` and `gitlab-packages`
buckets. Separate identities restrict OpenTofu to its state bucket and GitLab
to artifacts/packages. The role creates missing buckets/users and upserts the
desired policies without deleting existing objects or resetting user secrets.
Verification authenticates as each scoped identity and lists its buckets.

The existing credentials are encrypted in the all-group vault, alongside the
root and backup credentials needed by the role. The OpenTofu identity matches
the project's masked AWS CI variables; the GitLab identity matches its existing
object-storage connection secret. Preserve those consumers if credentials are
deliberately rotated. The role does not restore state or historical artifacts;
normal reconciliation never replaces the current state object.

From the Ansible directory, run `ansible-playbook playbooks/setup/rustfs.yml
--limit storage.local.hejsan.xyz --tags rustfs_gitlab_storage` to reconcile only
this storage configuration. Use `--check --diff` first. A normal full role run
also manages it; disabling the optional configuration leaves existing data and
identities in place.

## Live protection capacity

A restricted DynamicUser systemd service publishes `__protection/capacity.json` in the dedicated v2 bucket every five minutes. It verifies the required mergerfs mount and reports available bytes and a timestamp. Systemd supplies only the v2 bucket credentials through `LoadCredential`; no root S3 identity is used. The protection gate must reject missing or stale reports and subtract the measured additional retained-backup forecast before applying the absolute free-space floor. This report is a monitoring object, outside LINSTOR backup retention.
