# Build gpu-unlock packages on eligible hosts from a pinned revision

The GPU unlock role will build and install gpu-unlock's Debian package locally
from a full, Renovate-managed upstream commit SHA, rather than consuming a
separate package repository or a floating branch. This preserves
kernel-specific early-boot integration and makes the deployed source revision
reviewable without adding package publishing infrastructure.
