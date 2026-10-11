# Home Assistant local voice

Configures Home Assistant to use the local Swedish voice stack:

- Ollama at `ollama.local.hejsan.xyz`
- Wyoming Whisper at `wyoming-whisper.local.hejsan.xyz:10300`
- Wyoming Piper at `wyoming-piper.local.hejsan.xyz:10200`
- Swedish Alma TTS voice `sv_SE-alma-medium`
- An Ollama conversation subentry using `qwen2.5:3b`
- An Assist pipeline named `Local Swedish`

The role uses the current Home Assistant config-subentry API for Ollama. It
does not modify or remove existing Assist pipelines. The Home Assistant API
token is read from `vault_homeassistant_token` and is only passed to the local
configuration command through its environment.

Run it explicitly from the Ansible directory:

```bash
ansible-playbook playbooks/setup/home-assistant-voice.yml --ask-vault-pass
```

The Wyoming services are deployed by Flux in Kubernetes and exposed through
Traefik TCP routes. This role only verifies those routes and configures
Home Assistant. It no longer deploys Docker Compose services on the GPU host.

The role connects to HassOS through
`http://homeassistant.local.hejsan.xyz:8123` and
expects `vault_homeassistant_token` in the encrypted
`inventory/group_vars/all/vault.yml`. It uses Home Assistant's API and does
not require SSH access to HassOS.

The active conversation model is `qwen2.5:3b`, a non-thinking instruct model
with a roughly 1.9 GB Ollama image. This keeps response latency and GPU memory
use suitable for the GTX 1070 while avoiding Qwen3's reasoning stream being
sent to voice TTS.

The Piper image embeds the Alma voice model and runs it CPU-only. The role
updates the existing `Local Swedish` pipeline when its TTS voice changes and
clears Home Assistant's TTS cache after the change.

The `Local Swedish to English` pipeline uses an English conversation language,
Swedish STT, and Kokoro `af_heart`. Local intents are preferred where HA can
match them in the pipeline language; Swedish time queries use the English
agent's GetDateTime tool.

Managed agent names include a SHA-256 configuration revision. Changing model,
prompt or history creates a new agent and switches the existing pipeline;
unchanged settings reuse the agent. This avoids stale options because HA's
subentry list API does not expose configuration data.

`home_assistant_voice_cleanup_legacy` defaults to true after the validated
migration. It removes the inventoried obsolete agents and the unused direct-host Ollama
integration. Cleanup checks all pipeline references and saves a mode-0600
inventory snapshot under `/tmp/home-assistant-voice-cleanup-*.json`. Existing
user-created entries are preserved. Previous agent settings remain in Git
history and can be recreated by running the role from the corresponding revision.

Run `playbooks/maintenance/retire-legacy-voice.yml` once the Kubernetes services
are healthy. It removes the two legacy Docker containers, disables host Ollama,
and archives `/opt/docker/wyoming-voice` as `.retired`. Model directories
`/opt/appdata/wyoming-voice` and `/var/lib/ollama` remain available for rollback.

For timing diagnostics, run `files/probe.py` with `HOME_ASSISTANT_TOKEN` in its
environment. It accepts `--pipeline`, `--text` and `--count`, consumes the real
TTS media stream and reports intent, first-media-byte and completion timings.
These measurements exclude microphone capture, STT and physical speaker delay;
they must not be presented as end-to-end hardware latency.

## Staged bilingual router

`home_assistant_voice_router_enabled: true` enables the custom Swedish-native /
English-output router installer. Supply a published archive URL and its SHA-256.
The role uses the admin token to configure key-only SSH on port 2222, preserving
existing authorized keys. The jumphost private key never leaves the jumphost.
SSH host identity is pinned from the authenticated Supervisor terminal.

Router tasks run without sudo so downloads and SSH trust belong to the execution
user. Run from the `ansible/` folder in a clean, isolated checkout on the jumphost;
do not overwrite its existing dirty checkout. The normal Swedish pipeline remains
Alma-based. The candidate is `Local Swedish to English — Router Test`, with `sv`
conversation input, Kokoro output, and outer `prefer_local_intents: false`.

Promotion is a separate `home_assistant_voice_router_promote: true` run. It requires
a private JSON acceptance file recording `release_sha256`, `model`, the pinned
`whisper_revision`, timezone-aware `tested_at` within seven days,
`regression_questions` of at least 40, and true `hardware_passed`,
`swedish_pipeline_passed`, `gpu_concurrent_passed`, `regression_suite_passed`.
These assertions must reflect actual tests, not text-only smoke tests.

Cleanup is opt-in: set `home_assistant_voice_router_cleanup_owned: true` and
`home_assistant_voice_router_ownership_file` only after promotion. The inventory
contains exact pipeline ID/name, subentry parent ID/subentry ID/title, or config
entry ID/domain/title. Start from `files/router-ownership.example.json` and
populate only verified migration-owned objects. `cleanup_router.py` previews
without `--apply`. All pipeline references and hardware selections are checked;
renamed, selected, shared, or referenced objects cause refusal. Remove obsolete
pipelines in one run, then re-preview agents in another run.

Before deleting objects, private durable pipeline/hardware snapshots and actual
HA `.storage` backups are saved, alongside the previous integration directory on
HA. Keep them for at least seven days after hardware acceptance. Storage contains
secrets: never commit it. Full storage restore is manual, with HA stopped and
careful review of unrelated changes; it is not an automatic rollback mechanism.
No models, PVCs, or backups are automatically purged. Their reference audit and
explicit purge remain separate operations. Revert the Flux candidate overlay and
restore the saved pipeline engine/settings for immediate configuration rollback.
