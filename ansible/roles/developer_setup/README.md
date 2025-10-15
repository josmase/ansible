# Developer Setup Role

This role sets up a local development environment for Ansible development, including:
- Kubernetes configuration from master nodes
- Directory structure setup
- Permissions management

## Requirements

- Ansible 2.9 or higher
- Access to Kubernetes master nodes (if using Kubernetes configuration)

## Role Variables

### Default Variables

| Variable | Description | Default |
|----------|-------------|---------|
| kubernetes_config_mode | File permissions for kube config | '0600' |
| kubernetes_config_dir | Directory for Kubernetes config | "/home/{{ ansible_user }}/.kube" |
| kubernetes_master_host | First k3s master node | groups['k3s_masters'][0] |
| kubernetes_master_user | User on master node | hostvars[kubernetes_master_host]['ansible_user'] |

### Variable Resolution

The role automatically:
1. Finds the first k3s master node from the inventory group 'k3s_masters'
2. Gets the ansible_user from that host's variables
3. Uses these to fetch the Kubernetes configuration

If no k3s master nodes are found, the Kubernetes config fetch task will be skipped.

## Dependencies

None. This role is self-contained and does not rely on external roles.
- Git installed locally

## Role Variables

```yaml
# Required Variables
git_email: "user@example.com"      # Git user email
git_name: "User Name"              # Git user name

# Optional Variables with defaults
ansible_root_dir: "{{ playbook_dir }}/.."  # Root directory of Ansible project
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: developer_setup
      vars:
        git_email: "developer@company.com"
        git_name: "John Doe"
```

## License

MIT

## Author Information

Created by josmase