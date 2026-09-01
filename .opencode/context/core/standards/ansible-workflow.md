# Ansible Playbook Execution Workflow

## Overview
This document outlines the standard workflow for executing Ansible playbooks in the infrastructure repository, specifically for applying changes to Transmission and other containerized services.

## Prerequisites
- Access to the ansible server (jumphost) via SSH
- Repository cloned on the ansible server
- Required Ansible collections installed
- Vault password file available (if using encrypted variables)

## Standard Execution Workflow

### 1. Access the Ansible Server
```bash
# Using SSH config alias
ssh ansible

# Or using full hostname
ssh ubuntu@ansible.local.hejsan.xyz
```

### 2. Navigate to the Repository
```bash
cd /home/ubuntu/repo/ansible
```

### 3. Update Repository (Handle Local Changes)
If you have local changes that might conflict with upstream:
```bash
# Stash local changes
git stash

# Pull latest changes
git pull origin main

# Reapply stashed changes if needed (review carefully)
# git stash pop
```

If you have no local changes or want to discard them:
```bash
# Reset to match origin/main
git reset --hard origin/main
git pull origin main
```

### 4. Install Required Collections (If Needed)
```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

### 5. Ensure Vault Password File is Available
```bash
# Copy from ansible directory if needed
cp ansible/.vault_pass .
```

### 6. Execute the Playbook
```bash
# Set ANSIBLE_CONFIG to use the local ansible.cfg
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ansible/inventory/production.ini \
  ansible/playbooks/setup/base.yml \
  --limit media_services
```

### 7. Target-Specific Execution
For more targeted execution, you can:
- Limit to specific hosts: `--limit media.local.hejsan.xyz`
- Run specific tags: `--tags docker,templates,containers`
- Check mode (dry run): Add `--check` flag
- Verbose output: Add `-v` (up to `-vvv` for debugging)

## Transmission-Specific Notes

When applying Transmission configuration changes, the playbook will:
1. Update the Transmission docker-compose template
2. Create required directory structure on the NFS mount:
   - `/mnt/storage/downloads/complete`
   - `/mnt/storage/downloads/incomplete`
   - `/mnt/storage/downloads/watch`
3. Deploy the Transmission settings.json file with proper download directory configuration
4. Restart the Transmission service

## Troubleshooting

### Common Issues

#### Vault Password File Missing
```
ERROR! The vault password file /path/to/.vault_pass was not found
```
Solution: Ensure the vault password file exists in the expected location:
```bash
ls -la ansible/.vault_pass
# If missing, copy from the ansible directory:
cp ansible/ansible/.vault_pass ansible/
```

#### Role Not Found Errors
```
ERROR! the role 'gantsign.antigen' was not found
```
Solution: Ensure required roles are installed in the galaxy_role directory:
```bash
ls -la ansible/galaxy_role/gantsign.antigen
# If missing, they should be installed via the roles_path configuration
```

#### Inventory Parsing Errors
```
[WARNING]: Unable to parse /path/to/inventory/production.ini as an inventory source
```
Solution: Verify you're using the correct inventory path:
```bash
-i ansible/inventory/production.ini
```

#### Temporary Directory Issues
```
FileNotFoundError: [Errno 2] No usable temporary directory found
```
Solution: This is a system issue on the target host. Ensure /tmp, /var/tmp, or /usr/tmp are available and writable.

## Verification After Execution

After successful playbook execution, verify:
1. Transmission container is running with updated configuration
2. Directory structure exists on the NFS mount:
   ```bash
   ls -la /mnt/storage/downloads/
   # Should show: complete/  incomplete/  watch/
   ```
3. Settings are applied correctly:
   ```bash
   # Check inside the container
   docker exec transmission cat /config/settings.json | grep -A 3 -B 1 "download-dir"
   # Should show proper paths to /mnt/storage/downloads/complete
   ```

## Related Workflows
- For development/testing: Use `--check --diff` flags to preview changes
- For service-specific updates: Limit to specific service playbooks when available
- For emergency fixes: Can target specific hosts with `--limit <hostname>`