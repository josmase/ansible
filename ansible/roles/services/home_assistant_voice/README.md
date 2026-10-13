# Home Assistant local voice

Configures Home Assistant to use the local voice stack. The default is the
single bilingual router pipeline; the legacy two-pipeline configuration is
available only when `home_assistant_voice_router_enabled` is explicitly false.

- Ollama at `ollama.local.hejsan.xyz`
- Wyoming Whisper at `wyoming-whisper.local.hejsan.xyz:10300`
- The bilingual router using `ha-qwen3-4b-instruct:2507-q4km`
- Swedish Whisper input and Kokoro `af_heart` English output

The role stages the router pipeline without selecting it on the hardware. The Home
Assistant API token is read from `vault_homeassistant_token` and is only passed
to the local configuration command through its environment.

Run it explicitly from the Ansible directory:

```bash
ansible-playbook playbooks/setup/home-assistant-voice.yml --ask-vault-pass
```

The Wyoming services are deployed by Flux in Kubernetes and exposed through
Traefik TCP routes. This role only verifies those routes and configures
Home Assistant. It no longer deploys Docker Compose services on the GPU host.

The role connects to HassOS through
`http://homeassistant.local.hejsan.xyz:8123` and expects
`vault_homeassistant_token` in the encrypted
`inventory/group_vars/all/vault.yml`. In the default router mode it also uses
the key-only Terminal & SSH add-on to install the custom integration.

The active router model is `ha-qwen3-4b-instruct:2507-q4km`. Ollama is
configured for one loaded model on the GTX 1070; do not configure another HA
conversation agent to load a different model on this endpoint while the router
is active, because that evicts the router model and fails the readiness check.

The current Assist configuration has a single preferred pipeline named
`Local Swedish to English — Router Test`. The former Alma/Piper Swedish
pipeline is not part of this active flow.

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

## Bilingual router

`home_assistant_voice_router_enabled: true` (the default) enables the custom
Swedish-input / English-output router installer. Supply a published archive URL and its SHA-256.
The role uses the admin token to configure key-only SSH on port 2222, preserving
existing authorized keys. The jumphost private key never leaves the jumphost.
SSH host identity is pinned from the authenticated Supervisor terminal.

Router tasks run without sudo so downloads and SSH trust belong to the execution
user. Run from the `ansible/` folder in a clean, isolated checkout on the jumphost;
do not overwrite its existing dirty checkout. The candidate router pipeline is
`Local Swedish to English — Validation`, with Swedish STT, Kokoro output, and
outer `prefer_local_intents: false`. An idempotent staging rerun preserves this
pipeline without selecting it. `Swedish voice evaluation — No actions` is a
separate recording-only pipeline that cannot call an intent, LLM, or service.

Promotion is a separate `home_assistant_voice_router_promote: true` run. It requires
a private JSON acceptance file and a release manifest binding the exact archive,
Ollama digest, pinned STT/TTS images, STT revision, pipeline configuration, and
non-secret router settings. It requires 80 recordings (40 held out), real speaker
playback, search, idempotency, GPU-concurrency and regression passes. It refuses
unsafe/duplicate execution, OOMs, playback failures, insufficient free VRAM, or
timings beyond the documented gates. These assertions must reflect actual tests,
not text-only smoke tests.

### Guided hardware recording

After the validation pipeline has been deployed, run the capture helper once per
phrase from the jumphost. It temporarily selects the no-action recording pipeline,
arms a Home Assistant capture, then restores both Voice selectors even on failure.
The WAV and adjacent metadata are mode `0600`, must be new paths, and are ignored
by Git:

```bash
HOME_ASSISTANT_TOKEN="…" python3 roles/services/home_assistant_voice/files/record_voice.py \
  --url http://homeassistant.local.hejsan.xyz:8123 \
  --output ~/.local/state/home-assistant-voice/recordings/001.wav \
  --expected 'Tänd lamporna i sovrummet'
```

When it prints “Recording is armed”, wake the hardware and say the expected
phrase once. The capture contains microphone audio; keep it on the jumphost and
do not commit or upload it.

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
