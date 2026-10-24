# Toolbox host prerequisites

Installs Docker Engine and the Docker Compose plugin on Ubuntu 26.04 x86_64,
starts Docker, and adds the current Ansible user to the `docker` group. The role
does not create application directories, deploy Compose files, clone projects,
or install or enroll Tailscale.

Run it against the inventoried `tdarr-3080` workstation:

```sh
ansible-playbook playbooks/setup/toolbox_host_prerequisites.yml --limit tdarr-3080 -K
```

Ansible check mode previews the Docker source change while skipping the key
download, APT package/cache operations, and Docker service operations. Those
operations require the source and package changes to be applied first.

After the first run, the user must log out and back in (or start a new login
session) for the new group membership to take effect. Docker group access grants
root-equivalent privileges on the host.
