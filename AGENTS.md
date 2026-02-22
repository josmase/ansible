# Ansible Best Practices Guide

## Directory Structure
```
ansible/
├── ansible.cfg             # Ansible configuration file
├── inventory/             # Inventory directory
│   ├── production.ini    # Production inventory file
│   ├── staging.ini       # Staging inventory file
│   ├── group_vars/       # Group-specific variables
│   │   ├── all/         # Variables for all groups
│   │   │   ├── main.yml # Non-sensitive variables
│   │   │   └── vault.yml # Group-level encrypted variables
│   │   └── [group]/     # Group-specific variables
│   └── host_vars/       # Host-specific variables
├── collections/          # Collections requirements
│   └── requirements.yml  # Collection dependencies
├── playbooks/           # Playbook files
│   ├── site.yml        # Main entry point playbook
│   ├── vars/           # Playbook variables
│   │   ├── common.yml  # Common variables
│   │   └── vault.yml   # Global encrypted variables
│   ├── setup/          # Setup playbooks
│   ├── maintenance/    # Maintenance tasks
│   └── services/       # Service deployment playbooks
└── roles/              # Reusable roles grouped by domain
  ├── core/
  ├── container/
  ├── platform/
  ├── storage/
  ├── services/
  ├── workstation/
  └── validation/
    └── role_name/      # Individual role
      ├── defaults/   # Default variables
      ├── files/      # Static files
      ├── handlers/   # Notification handlers
      ├── meta/      # Role metadata
      ├── tasks/     # Task definitions
      ├── templates/ # Jinja2 templates
      └── vars/      # Role variables
```

## Naming Conventions
1. **Files and Directories**
   - Use lowercase letters
   - Use underscores for spaces
   - Use `.yml` extension for YAML files
   - Use descriptive names: `setup_docker.yml`, not `setup.yml`

2. **Variables**
   - Use snake_case: `nfs_mount_point`, not `nfsMountPoint`
   - Prefix role variables with role name: `docker_compose_dir`
   - Use descriptive names: `maintenance_calendar`, not `cal`

## Role Independence and Variable Organization
1. **Role Independence Principles**
   - Roles should be self-contained units
   - All required variables must have defaults
   - Never rely on variables from other roles
   - Document any optional external variables
   - Example of role independence:
     ```yaml
     # Bad - Relying on global variables
     tasks/main.yml:
       - name: Create docker directories
         file:
           path: "{{ global_docker_dir }}/{{ item }}"
           state: directory
     
     # Good - Self-contained role
     defaults/main.yml:
       docker_base_dir: /opt/docker
       docker_subdirs:
         - compose
         - scripts
     
     tasks/main.yml:
       - name: Create docker directories
         file:
           path: "{{ docker_base_dir }}/{{ item }}"
           state: directory
         loop: "{{ docker_subdirs }}"
     ```

2. **Variable Precedence Order** (highest to lowest):
   1. Command line `-e` variables
   2. Playbook vars/ directory variables
   3. Host variables (`inventory/host_vars/`)
   4. Group variables (`inventory/group_vars/`)
   5. Role defaults (`roles/x/defaults/`)
   6. Inventory variables

2. **Variable File Organization**
   ```yaml
   # group_vars/all/main.yml - Non-sensitive group variables
   kubernetes_config_dir: "~/.kube"
   ansible_sudo_pass: "{{ vault_default_sudo_pass }}"
   
   # vars/vault.yml - Sensitive variables (encrypted)
   vault_default_sudo_pass: "secretpassword"
   
   # roles/docker_setup/defaults/main.yml - Role defaults
   docker_compose_dir: "/opt/docker/compose"
   ```

3. **Distribution-specific Variables**
   ```yaml
   # roles/usb_module_setup/defaults/main.yml
   # Package names by distribution
   debian_packages:
     - usbutils
     - linux-modules-extra-{{ ansible_kernel }}
   
   arch_packages:
     - usbutils
     - linux-headers
   ```

## Role Organization
1. **Role Structure**
   ```
   roles/docker/
   ├── README.md        # Role documentation and usage examples
   ├── defaults/        # Default variables
   │   └── main.yml    # Default role variables (lowest precedence)
   ├── files/          # Static files
   ├── handlers/       # Notification handlers
   │   └── main.yml   # Handler definitions
   ├── meta/          # Role metadata and dependencies
   │   └── main.yml  # Dependencies and compatibility info
   ├── tasks/         # Task definitions
   │   ├── main.yml  # Main task entry point
   │   ├── install.yml # Installation tasks
   │   └── config.yml # Configuration tasks
   ├── templates/     # Jinja2 templates
   └── vars/         # Role variables (higher precedence)
       └── main.yml  # Fixed role variables
   ```

2. **Role Independence**
   - Keep roles independent of global variables
   - Define all required variables in defaults/main.yml
   - Override defaults through inventory or playbook vars when needed
   - Example of a self-contained role:
     ```yaml
     # roles/docker_setup/defaults/main.yml
     ---
     # Base paths - don't rely on global variables
     docker_base_dir: "/opt/docker"
     docker_compose_dir: "{{ docker_base_dir }}/compose"
     docker_scripts_dir: "{{ docker_base_dir }}/scripts"
     docker_data_dir: "{{ docker_base_dir }}/data"
     
     # Timer configuration - self-contained in the role
     docker_timers:
       - name: maintenance
         schedule: "*-*-* 04:00:00"
       - name: staleFileHandleHandler
         schedule: "*-*-* *:00:00"
     
     # Distribution-specific packages
     docker_debian_packages:
       - docker-ce
       - docker-ce-cli
     docker_arch_packages:
       - docker
     ```

3. **Role Best Practices**
   - Keep roles focused and single-purpose
   - Make roles distribution-agnostic:
     ```yaml
     # Example from USB module setup
     - name: Install required packages for Debian-based systems
       apt:
         name: "{{ debian_packages }}"
         state: present
       when: ansible_os_family == "Debian"

     - name: Install required packages for Arch-based systems
       pacman:
         name: "{{ arch_packages }}"
         state: present
       when: ansible_os_family == "Archlinux"
     ```
   - Use descriptive task names for better logging
   - Document role variables in defaults/main.yml with examples
   - Use handlers for service restarts
   - Include role dependencies in meta/main.yml
   - Split complex task files into logical subfiles
   - Provide working examples in README.md

4. **Role Documentation**
   ```markdown
   # Docker Setup Role
   
   Sets up Docker environment with maintenance scripts and timers.
   
   ## Variables
   All variables are defined in defaults/main.yml with sensible defaults.
   No external variables required.
   
   ### Optional Variables
   Override these in your inventory if needed:
   - docker_base_dir: Base directory for Docker files
   - docker_timers: List of maintenance timers
   
   ## Dependencies
   None. This role is self-contained and does not rely on external roles
   or variables.
   ```

## Security Best Practices
1. **Vault Organization**
   - Store global encrypted variables in `playbooks/vars/vault.yml`
   - Store group-specific encrypted variables in `inventory/group_vars/[group]/vault.yml`
   - Never commit unencrypted sensitive data
   - Use meaningful vault IDs: `--vault-id prod@prompt`

2. **Vault Usage in Playbooks**
   - Always use absolute paths with playbook_dir:
     ```yaml
     vars_files:
       - "{{ playbook_dir }}/../../vars/vault.yml"  # From playbooks/setup/
       - "{{ playbook_dir }}/../vars/vault.yml"     # From playbooks/
     ```
   - Define vault_vars_file in common.yml for consistent reference:
     ```yaml
     # In playbooks/vars/common.yml
     vault_vars_file: "{{ playbook_dir }}/../vars/vault.yml"
     
     # In playbooks
     vars_files:
       - vars/common.yml
       - "{{ vault_vars_file }}"
     ```
   - Separate sensitive and non-sensitive variables:
     ```yaml
     # In group_vars/all/main.yml
     ansible_sudo_pass: "{{ vault_default_sudo_pass }}"
     
     # In vars/vault.yml (encrypted)
     vault_default_sudo_pass: "secretpassword"
     ```

3. **File Permissions**
   - Set explicit file permissions with `mode`
   - Use restrictive permissions for sensitive files
   - Always set owner and group for files

## Task Writing
1. **General Guidelines**
   - Use YAML dictionary syntax for tasks
   - Always name your tasks descriptively
   - Use `state: present` explicitly (don't rely on defaults)
   - Include `when` conditions at the task level, not play level
   - Split complex plays into separate task files:
     ```yaml
     # main.yml
     - name: Include installation tasks
       include_tasks: install.yml
     
     - name: Include configuration tasks
       include_tasks: config.yml
     ```

2. **Task Organization**
   - Group related tasks in separate files
   - Use include_tasks for better maintainability
   - Keep task files focused and manageable
   - Use meaningful file names:
     ```
     tasks/
     ├── main.yml      # Main entry point
     ├── install.yml   # Installation tasks
     ├── config.yml    # Configuration tasks
     └── service.yml   # Service management
     ```

3. **Idempotency and Safety**
   - Tasks should be idempotent (safe to run multiple times)
   - Use `creates`, `removes`, or `stat` module to check existing state
   - Prefer package modules over command modules
   - Handle system-specific differences:
     ```yaml
     - name: Ensure kernel modules are loaded
       modprobe:
         name: "{{ item }}"
         state: present
       loop:
         - ftdi_sio
         - usbserial
       when: ansible_system == "Linux"
     ```

## Inventory Management
1. **Group Organization**
   - Use meaningful group names
   - Use group_vars for common configurations
   - Use children groups for hierarchy
   - Document group purpose in inventory

2. **Host Management**
   - Use FQDN or IP addresses consistently
   - Group hosts by function AND environment
   - Use `ansible_host` for IP addresses when hostname differs

## Testing and Validation
1. **Before Running**
   - Use `--check` mode to verify changes
   - Use `--diff` to see file changes
   - Validate syntax: `ansible-playbook --syntax-check`

2. **During Development**
   - Test on a single host before running on many
   - Use tags for selective execution
   - Use `--limit` to restrict scope

## Error Handling
1. **Task Level**
   - Use `ignore_errors` sparingly and document why
   - Use `failed_when` for custom failure conditions
   - Use `changed_when` to control changed status

2. **Play Level**
   - Set `any_errors_fatal` for critical plays
   - Use `max_fail_percentage` for controlled failures
   - Implement proper error handling in custom modules

## Documentation
1. **In Code**
   - Document non-obvious task purposes
   - Include examples in role README.md
   - Document required variables
   - Explain complex conditions or loops

2. **External**
   - Maintain inventory documentation
   - Document deployment procedures
   - Keep change logs
   - Document recovery procedures

## Playbook Organization and Best Practices
1. **Playbook Structure**
   ```yaml
   # site.yml - Main entry point
   - name: Validate configuration
     hosts: all
     vars_files:
       - vars/common.yml
       - "{{ vault_vars_file }}"
     roles:
       - variable_validation

   # setup/base.yml - Setup playbook
   - name: Base system configuration
     hosts: all_servers
     vars_files:
       - "{{ playbook_dir }}/../../vars/vault.yml"
     roles:
       - base_setup
   ```

2. **Distribution-agnostic Design**
   - Use OS family facts for conditionals:
     ```yaml
     when: ansible_os_family == "Debian"
     when: ansible_os_family == "Archlinux"
     ```
   - Define OS-specific variables in defaults
   - Use package module for cross-platform support
   - Handle service differences per OS

3. **Timer and Service Management**
   - Use proper systemd calendar formats
   - Implement consistent scheduling:
     ```yaml
     # Example from docker_setup
     timers:
       - name: maintenance
         schedule: "*-*-* 04:00:00"
       - name: staleFileHandleHandler
         schedule: "*-*-* *:00:00"
     ```
   - Handle service dependencies
   - Use handlers for restarts

4. **Maintenance and Updates**
   - Implement rolling updates
   - Handle reboots safely
   - Validate configurations
   - Monitor service health
   - Add monitoring role
   - Improve error handling

4. **Development Workflow**
   - Add development environment
   - Implement testing framework
   - Add CI/CD pipeline
   - Improve documentation

## Additional Resources
- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Ansible Examples](https://github.com/ansible/ansible-examples)
- [Ansible Galaxy](https://galaxy.ansible.com/)