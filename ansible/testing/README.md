# Ansible Testing with Docker

This directory contains a complete Docker-based testing environment for the POSIX Hardening Ansible playbooks.

## Overview

The testing setup simulates a realistic multi-host environment where you can safely test hardening playbooks without affecting production systems.

### Components

- **Dockerfile**: Debian 12-based target system with SSH, systemd, and required packages
- **docker-compose.yml**: Multi-container setup with 2 target hosts and an Ansible controller
- **inventory-docker.ini**: Ansible inventory configured for Docker containers
- **test-runner.sh**: Automated testing script for common workflows

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- At least 4GB free RAM
- 10GB free disk space

### Run Complete Test Cycle

```bash
cd ansible/testing
./test-runner.sh full
```

This will:
1. Generate SSH keys
2. Start Docker containers
3. Test SSH connectivity
4. Run preflight checks
5. Run dry-run hardening
6. Prompt for full hardening
7. Run validation tests

## Step-by-Step Testing

### 1. Setup Environment

Generate SSH keys and prepare the environment:

```bash
./test-runner.sh setup
```

### 2. Start Containers

Launch all Docker containers:

```bash
./test-runner.sh start
```

This creates:
- `posix-hardening-target1` - First target host (172.20.0.10)
- `posix-hardening-target2` - Second target host (172.20.0.11)
- `posix-hardening-controller` - Ansible control node (172.20.0.2)

### 3. Test SSH Connectivity

Verify SSH access to target containers:

```bash
./test-runner.sh ssh-test
```

### 4. Run Preflight Checks

Execute pre-deployment validation:

```bash
./test-runner.sh preflight
```

### 5. Run Dry-Run Test

Test hardening without making changes:

```bash
./test-runner.sh dryrun
```

### 6. Run Full Hardening

Apply all hardening scripts:

```bash
./test-runner.sh harden
```

### 7. Run Validation

Verify hardening was applied correctly:

```bash
./test-runner.sh validate
```

### 8. Stop Containers

Stop all running containers:

```bash
./test-runner.sh stop
```

### 9. Clean Up

Remove containers and volumes:

```bash
./test-runner.sh clean
```

## Manual Testing

### Access the Ansible Controller

```bash
docker exec -it posix-hardening-controller /bin/bash
```

From inside the controller, you can run any Ansible command:

```bash
# List hosts
ansible -i inventory-docker.ini all --list-hosts

# Ping all hosts
ansible -i inventory-docker.ini all -m ping

# Run preflight
ansible-playbook -i inventory-docker.ini preflight.yml

# Run site playbook with dry-run
ansible-playbook -i inventory-docker.ini site.yml -e "dry_run=1"

# Run specific tags
ansible-playbook -i inventory-docker.ini site.yml --tags "deploy,priority1"
```

### Access Target Hosts

```bash
# Access target1
docker exec -it posix-hardening-target1 /bin/bash

# Access target2
docker exec -it posix-hardening-target2 /bin/bash
```

### SSH to Targets from Controller

```bash
docker exec -it posix-hardening-controller ssh -i /root/.ssh/id_rsa ansible@172.20.0.10
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Network: 172.20.0.0/16            │
│                                                               │
│  ┌──────────────────┐                                        │
│  │   Controller     │  Ansible Control Node                  │
│  │  172.20.0.2      │  - Runs playbooks                      │
│  │                  │  - Has SSH keys                        │
│  └────────┬─────────┘  - Access to all targets              │
│           │                                                   │
│           │                                                   │
│  ┌────────▼─────────┐          ┌─────────────────┐          │
│  │    Target 1      │          │    Target 2     │          │
│  │  172.20.0.10     │          │  172.20.0.11    │          │
│  │  Port: 2201      │          │  Port: 2202     │          │
│  │                  │          │                 │          │
│  │  - Debian 12     │          │  - Debian 12    │          │
│  │  - systemd       │          │  - systemd      │          │
│  │  - SSH server    │          │  - SSH server   │          │
│  └──────────────────┘          └─────────────────┘          │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Testing Scenarios

### Scenario 1: Single Host Testing

Test against only target1:

```bash
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini site.yml \
  --limit target1
```

### Scenario 2: Dry-Run Full Hardening

Test all changes without applying:

```bash
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini site.yml \
  -e "dry_run=1 run_full_hardening=true"
```

### Scenario 3: Priority Testing

Test only specific priority levels:

```bash
# Only Priority 1 (Critical)
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini site.yml \
  --tags "priority1"

# Priority 1 and 2
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini site.yml \
  --tags "priority1,priority2"
```

### Scenario 4: Rollback Testing

Test the rollback playbook:

```bash
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini rollback.yml
```

## Troubleshooting

### Containers Won't Start

Check if ports are already in use:

```bash
# Check port 2201
lsof -i :2201

# Check port 2202
lsof -i :2202
```

### SSH Connection Fails

1. Verify containers are running:
   ```bash
   docker ps
   ```

2. Check SSH service in target:
   ```bash
   docker exec posix-hardening-target1 systemctl status ssh
   ```

3. Test SSH from controller:
   ```bash
   docker exec posix-hardening-controller \
     ssh -v -i /root/.ssh/id_rsa ansible@172.20.0.10
   ```

### Playbook Fails

1. Check target system state:
   ```bash
   docker exec posix-hardening-target1 /bin/bash
   ```

2. Review logs:
   ```bash
   docker logs posix-hardening-target1
   docker logs posix-hardening-controller
   ```

3. Reset environment:
   ```bash
   ./test-runner.sh clean
   ./test-runner.sh start
   ```

## Container Resources

Each target container includes:

- **Volumes**:
  - `/var/lib/hardening` - Hardening state data
  - `/var/backups/hardening` - Backup snapshots
  - `/var/log` - System logs

- **Privileges**:
  - `SYS_ADMIN` - Required for systemd
  - `NET_ADMIN` - Required for firewall rules
  - `SYS_TIME` - Required for time synchronization

- **Network**:
  - Bridge network with static IPs
  - Full connectivity between containers
  - Isolated from host network

## Continuous Integration

This testing setup can be integrated into CI/CD pipelines:

```bash
#!/bin/sh
# CI test script

set -e

cd ansible/testing

# Run complete test cycle non-interactively
./test-runner.sh setup
./test-runner.sh start
./test-runner.sh ssh-test
./test-runner.sh preflight
./test-runner.sh dryrun

# Clean up
./test-runner.sh clean
```

## Best Practices

1. **Always start with dry-run**: Test changes without applying them
2. **Use preflight checks**: Validate environment before hardening
3. **Test incrementally**: Test by priority levels
4. **Review logs**: Check playbook output carefully
5. **Clean between tests**: Remove volumes to ensure clean state
6. **Snapshot before hardening**: Containers support creating backups

## Security Notes

- SSH keys are generated automatically for testing only
- Containers run with elevated privileges for systemd simulation
- Default passwords (ansible:ansible) are for testing only
- Network is isolated from host by default
- Do not use these configurations in production

## Advanced Usage

### Custom Test Configuration

Create a custom inventory:

```bash
cp inventory-docker.ini my-test-inventory.ini
# Edit as needed
docker exec posix-hardening-controller \
  ansible-playbook -i my-test-inventory.ini site.yml
```

### Debugging

Enable verbose output:

```bash
docker exec posix-hardening-controller \
  ansible-playbook -i inventory-docker.ini site.yml -vvv
```

### Persistent Testing

Keep containers running between test runs:

```bash
# Start once
./test-runner.sh start

# Run multiple tests
./test-runner.sh preflight
./test-runner.sh dryrun
# ... modify playbooks ...
./test-runner.sh dryrun

# Stop when done
./test-runner.sh stop
```

## Support

For issues or questions about Docker testing:

1. Check container logs: `docker logs <container-name>`
2. Review playbook output for errors
3. Verify SSH connectivity with `ssh-test` command
4. Reset environment with `clean` and `start` commands
5. Consult main Ansible README.md for playbook details
