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

Production enables `rustfs_gitlab_storage_enabled`. The GitLab chart uses the
`gitlab-object-storage` connection for artifacts, LFS, uploads, packages, and
Terraform state, so its identity is scoped to those five buckets. The
`gitlab-backup-object-storage` connection is separate; its temporary and archive
buckets are `gitlab-backups-tmp` and `gitlab-backups`. The role creates missing
GitLab and backup buckets additively, without deleting existing objects.

OpenTofu CI has a separate identity restricted to `gitlab-terraform-state`.
The role upserts the GitLab and OpenTofu policies without resetting user
secrets. Verification authenticates as each identity, lists its assigned
buckets, confirms both identities cannot list each other's unrelated buckets,
and checks that all configured buckets exist. Backup identity authorization
remains tied to the separate Flux-managed Secret and is not changed by this
role; verify it against the live RustFS policy before relying on backups.

The GitLab Container Registry currently uses the same key pair as the GitLab
object-storage identity. The role attaches an additional
`gitlab-container-registry` policy restricted to the configured registry
prefix within `linstor-backups`; it preserves the workload policy because the
identity is shared. As a result, both GitLab workload and registry permissions
are available to that shared identity. OpenTofu remains separate. The role
never removes or rewrites registry objects.

The existing GitLab and OpenTofu credentials are encrypted in the all-group
vault, alongside the root and backup credentials needed by the role. The
OpenTofu identity matches the project's masked AWS CI variables; the GitLab
identity matches the chart's object-storage connection secret. Preserve those
consumers if credentials are deliberately rotated. The role does not restore
state or historical artifacts; normal reconciliation never replaces the
current state object.

From the Ansible directory, run `ansible-playbook playbooks/setup/rustfs.yml
--limit storage.local.hejsan.xyz --tags rustfs_gitlab_storage` to reconcile only
this storage configuration. Use `--check --diff` first. A normal full role run
also manages it; disabling the optional configuration leaves existing data and
identities in place.

## Live protection capacity

A restricted DynamicUser systemd service publishes `__protection/capacity.json` in the dedicated v2 bucket every five minutes. It verifies the required mergerfs mount and reports available bytes and a timestamp. Systemd supplies only the v2 bucket credentials through `LoadCredential`; no root S3 identity is used. The protection gate must reject missing or stale reports and subtract the measured additional retained-backup forecast before applying the absolute free-space floor. This report is a monitoring object, outside LINSTOR backup retention.

## Dedicated GitLab Toolbox backup identity

`rustfs_gitlab_backup_identity_enabled` provisions a separate user and the
`gitlab-application-backups` policy scoped to `rustfs_gitlab_backup_buckets`.
The role creates missing buckets additively and never resets an existing user's
secret. Credentials must be stored in encrypted inventory and must match the
Flux-managed `gitlab-backup-object-storage` Secret. The assertion rejects
reused access keys, policy names, and overlapping workload or LINSTOR buckets.
The role verifies the new identity can list each backup bucket. Verify denied
access and the absence of additional policy attachments separately.

Deploy the Ansible change first, including the encrypted inventory variables,
and verify access before reconciling the corresponding Flux Secret. Keep the
old Secret available for rollback, and do not enable a backup schedule until
issue #5's recovery and operational checks pass. Disabling this feature leaves
the created identity, policy, and buckets in place; it does not revoke access.

The reconciliation uses the pinned `rustfs/rc` image's `jq` and JSON admin
user and policy listings. Existing users must be enabled, have no group
memberships, and have exactly the backup policy; an existing policy must match
the rendered document. A mismatch stops reconciliation before attaching
permissions. If creation succeeds but policy attachment fails, the next run
stops on the unassigned user. An operator must inspect that user's identity,
policy attachments and group memberships and confirm it is the intended new
backup user before attaching the reviewed backup policy using the RustFS admin
client. Re-run verification afterward; never adopt an unknown pre-existing user.

## Dedicated Registry identity and cutover

`rustfs_registry_dedicated_identity_enabled` provisions a distinct identity
using encrypted inventory credentials and the existing prefix-scoped Registry
policy. Existing users must already have exactly that policy and no group
memberships; unexpected accounts are not adopted. The workload identity keeps
its existing Registry policy while `rustfs_registry_shared_access_enabled` is
true. Provision and verify the new identity before applying the separately
reviewed Flux Registry Secret; its bucket and prefix remain unchanged.

After the Secret is active and Registry pulls and a test push succeed, remove
shared access in a separate reviewed change by setting
`rustfs_registry_shared_access_enabled: false`. The role requires the dedicated
identity, validates its policy and prefix listing before detaching the legacy
policy, and refuses to alter a workload identity with unexpected policies or
group membership. Check actual denied access after the change. To roll back,
restore the shared flag and reconcile before restoring the old Secret. Preserve
both identities and all Registry objects during the rollback window.

If user creation succeeds but policy attachment fails, the next run stops on
the unassigned user. Inspect the account and confirm ownership before manually
attaching the reviewed policy, then rerun verification; never adopt an unknown
user. The separate bucket migration remains a later operation and requires the
write freeze and final sync documented in the Flux repository.
