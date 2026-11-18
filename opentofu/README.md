# OpenTofu infrastructure

This directory contains the repository's OpenTofu roots. Use OpenTofu 1.13.1
(`tofu`), not Terraform. Each root pins its providers in a committed
`.terraform.lock.hcl` file.

## Roots

- `dns`: Cloudflare DNS records. Copy `tofu.tfvars.example` to the local,
  ignored `tofu.tfvars` file and provide the Cloudflare credentials and zone
  values.
- `virtual-machines`: Proxmox VMs and cloud image. Copy
  `tofu.tfvars.example` to the local, ignored `tofu.tfvars` file and provide
  Proxmox credentials, the image checksum, and the SSH public key.

Run commands from the individual root with the GitLab HTTP backend configured:

```sh
tofu init -lockfile=readonly
tofu fmt -check
tofu validate
tofu plan -var-file=tofu.tfvars
```

Do not apply a plan until it has been reviewed. The VM root must never replace
or destroy an existing VM during adoption.

Master VM memory is configured per node in `virtual-machines/variables.tf`.
For safe memory reduction, profile K3s first and lower one master allocation
per reviewed plan/apply, verifying etcd quorum and cluster recovery before
continuing. See `../docs/K3S_MASTER_MEMORY.md` for the profile, Go soft-limit,
and acceptance procedure.

## GitLab state and pipelines

The DNS and VM roots use the GitLab-managed states `dns` and
`virtual-machines`. Each root has a separate child pipeline. Merge requests
from the project can produce plans; main produces a new plan, which must be
reviewed before its manual apply. A saved plan fails if its state is stale, and
the apply job checks that its commit is at the tip of main immediately before
attempting to acquire the state lock. A concurrent apply fails immediately if
the lock is held; run and review a new pipeline. A main update can still occur
between that check and the apply; coordinate merges during an apply if that
distinction matters. To check
drift without a change, run a main pipeline in GitLab with `TOFU_ROOT` set to
`dns`, `virtual-machines`, or `all`.

Create a GitLab project file variable named `TOFU_VARS` for each environment
scope: `opentofu/dns` and `opentofu/virtual-machines`. Each file holds the
corresponding root's OpenTofu inputs, excluding the provider credentials.
Store the Cloudflare token in the masked `TF_VAR_api_token` project variable
scoped to `opentofu/dns`, and the Proxmox password in the masked
`TF_VAR_proxmox_password` project variable scoped to `opentofu/virtual-machines`.
For merge request summaries, configure a masked `TOFU_MR_COMMENT_TOKEN`
project variable for each of those two scopes. The token must be able to create
merge request notes through the GitLab API; a project access token limits its
scope to this project. Rotate it before expiry. Without it, MR plan jobs fail
after planning because they cannot publish the requested summary.
Only trusted people may push
branches or run pipelines in this project: jobs on internal branches can access
project variables. Keep human project membership limited to Maintainers and
Owners: the pipeline does not independently check an MR author's role, and an
internal Developer can run code that receives these variables. A Reporter bot
can post plan summaries without being able to push or run pipelines. Keep fork
pipelines in the parent project disabled. Plans
and state can contain private values; restrict access to the project and its
artifacts. MR activity summaries contain resource addresses and action counts,
not planned values. Saved plan artifacts expire after one day.

For local use, configure the HTTP backend with environment variables, including
`TF_HTTP_ADDRESS`, `TF_HTTP_LOCK_ADDRESS`, `TF_HTTP_UNLOCK_ADDRESS`,
`TF_HTTP_LOCK_METHOD=POST`, `TF_HTTP_UNLOCK_METHOD=DELETE`, and GitLab
credentials in `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD`. The state address is
`$CI_API_V4_URL/projects/<project-id>/terraform/state/<state-name>`; lock and
unlock use the same address with `/lock` appended. Do not put credentials in
backend configuration files or command-line arguments. Run the existing plan
command with a private local variables file.

## Migration and recovery

Migrate DNS first and then VMs. For each root, stop other writers and make
secure copies of the local state and backup. Configure the GitLab HTTP backend
and run `tofu init -migrate-state`; compare the retrieved remote state with the
source and review a fresh plan before proceeding. Stop and investigate any
unexpected changes; migration does not require applying a plan. If verification
fails, establish which copy is authoritative and restore the secure backup
before allowing writers. For a GitLab-state recovery, stop all writers and
download both the current and selected earlier version to private files using
`glab opentofu state download <state> [<serial>]`; inspect their resource
addresses and lineage without publishing their contents. After confirming the
intended version, use the configured backend's `tofu state push` to restore it;
an older serial requires `-force`, which bypasses safety checks and must only
be used after preserving the current state. Pull it again, compare it with the
selected version, and review a fresh plan before resuming writers. The original
DNS backup predates the two imports of `homeassistant.local` and
`kubernetes-214.local`; restoring it requires reimporting those records or
choosing a GitLab version that contains them. After both migrations are verified, retain the secure
backups and remove working-directory state copies. The existing state already
references OpenTofu registry provider addresses; do not run `state
replace-provider`.
