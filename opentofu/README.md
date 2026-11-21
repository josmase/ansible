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

Run local commands from the individual root with the GitLab HTTP backend
configured:

```sh
tofu init -input=false -lockfile=readonly -reconfigure
tofu fmt -check
tofu validate
tofu plan -input=false -lock=false -var-file=tofu.tfvars
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
`virtual-machines`. The parent `.gitlab-ci.yml` keeps root selection, changed
file rules, and the web pipeline's `TOFU_ROOT` selector. It starts the pinned
`ansible-opentofu@v4.2.0` component with `tf_root` set to the repository-relative
path (`opentofu/dns` or `opentofu/virtual-machines`) and `state_name` set to
`dns` or `virtual-machines`.

The component configures the GitLab HTTP backend with `CI_JOB_TOKEN`, pins
OpenTofu 1.13.1, and plans with the scoped `TOFU_VARS` File variable. Merge
request plans publish a summary containing resource addresses and actions, not
planned values. Main branch plans produce a saved plan artifact that expires
after one day. Apply is a blocking manual job on the default branch only; it
checks that the pipeline commit is still at the tip of the default branch
before applying the saved plan. If state changed after planning, or a
concurrent apply holds the lock, run and review a fresh pipeline. A branch
update can still happen between the tip check and apply, so coordinate merges
during an apply if needed. To check drift without a change, run a main pipeline
in GitLab with `TOFU_ROOT` set to `dns`, `virtual-machines`, or `all`.

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

`TOFU_VARS` is a GitLab File variable scoped to `opentofu/dns` or
`opentofu/virtual-machines`; local runs use the ignored `tofu.tfvars` file.
Pass provider secrets as `TF_VAR_*` environment variables locally and as masked
GitLab CI variables in the project. To use GitLab state locally, set the HTTP
backend environment variables for the state you selected. For example, from
the DNS root:

```sh
export TF_HTTP_ADDRESS="${GITLAB_API_V4_URL}/projects/${GITLAB_PROJECT_ID}/terraform/state/dns"
export TF_HTTP_LOCK_ADDRESS="${TF_HTTP_ADDRESS}/lock"
export TF_HTTP_UNLOCK_ADDRESS="${TF_HTTP_ADDRESS}/lock"
export TF_HTTP_LOCK_METHOD=POST
export TF_HTTP_UNLOCK_METHOD=DELETE
export TF_HTTP_USERNAME="${GITLAB_HTTP_USERNAME}"
export TF_HTTP_PASSWORD="${GITLAB_HTTP_PASSWORD}"
export TF_HTTP_RETRY_WAIT_MIN=5
```

Set the API URL, project ID, and credentials in your shell environment before
running the local commands. Use the `virtual-machines` state when working in
that root. Do not put credentials in backend configuration files or command
line arguments. The shared component handles backend setup and routine apply
in CI; local commands support initialization, formatting, validation, and
planning only.

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
selected version, and review a fresh plan before resuming writers. The original DNS backup predates the `homeassistant.local` import; restoring it requires reimporting that record or choosing a GitLab version that contains it. The retired worker record `kubernetes-214.local` must not be restored from an older state. After both migrations are verified, retain the secure
backups and remove working-directory state copies. The existing state already
references OpenTofu registry provider addresses; do not run `state
replace-provider`.
