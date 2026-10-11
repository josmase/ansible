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

The `Local Swedish to English` pipeline disables local intents so Swedish
queries such as the time query are answered by the English conversation agent
before being sent to Kokoro's English voice.
