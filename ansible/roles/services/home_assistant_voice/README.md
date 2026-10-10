# Home Assistant local voice

Configures Home Assistant to use the local Swedish voice stack:

- Ollama at `ollama.local.hejsan.xyz`
- Wyoming Whisper at `wyoming-whisper.local.hejsan.xyz:10300`
- Wyoming Piper at `wyoming-piper.local.hejsan.xyz:10200`
- An Ollama conversation subentry named `Local Qwen3`
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

The role connects to HassOS directly at `http://homeassistant.local:8123` and
expects `vault_homeassistant_token` in the encrypted
`inventory/group_vars/all/vault.yml`. It uses Home Assistant's API and does
not require SSH access to HassOS.
