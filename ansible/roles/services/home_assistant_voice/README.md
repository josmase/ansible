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
