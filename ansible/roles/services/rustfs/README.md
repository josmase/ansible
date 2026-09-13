# RustFS

Deploys a digest-pinned RustFS S3 endpoint on mergerfs. The systemd unit is
bound to the mergerfs mount so Docker cannot write below an absent mount.
Credentials must come from encrypted inventory variables.

