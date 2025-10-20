# Docker Testing Quick Start

Fast guide to get started with Docker-based Ansible testing.

## One Command Test

```bash
cd ansible/testing
./test-runner.sh full
```

This runs the complete test cycle:
1. Generate SSH keys
2. Start containers
3. Test SSH connectivity
4. Run preflight checks
5. Run dry-run hardening
6. Prompt for full hardening (optional)
7. Run validation

## Common Commands

```bash
# Setup and start
./test-runner.sh setup    # Generate SSH keys
./test-runner.sh start    # Start containers

# Testing
./test-runner.sh ssh-test # Test SSH connectivity
./test-runner.sh preflight # Run preflight checks
./test-runner.sh dryrun   # Dry-run hardening (Priority 1)
./test-runner.sh harden   # Full hardening
./test-runner.sh validate # Run validation

# Cleanup
./test-runner.sh stop     # Stop containers
./test-runner.sh clean    # Remove all containers and volumes
```

## Manual Testing

Access the Ansible controller:

```bash
docker exec -it posix-hardening-controller /bin/bash
```

Run commands inside:

```bash
# Test connectivity
ansible -i inventory-docker.ini all -m ping

# Run preflight
ansible-playbook -i inventory-docker.ini preflight.yml

# Run site with dry-run
ansible-playbook -i inventory-docker.ini site.yml -e "dry_run=1"

# Run specific priority
ansible-playbook -i inventory-docker.ini site.yml --tags priority1
```

## Access Targets

```bash
# SSH to target1 from controller
docker exec -it posix-hardening-controller \
  ssh -i /root/.ssh/id_rsa ansible@172.20.0.10

# Direct bash access to target1
docker exec -it posix-hardening-target1 /bin/bash

# Direct bash access to target2
docker exec -it posix-hardening-target2 /bin/bash
```

## Container Details

- **target1**: 172.20.0.10 (port 2201 on host)
- **target2**: 172.20.0.11 (port 2202 on host)
- **controller**: 172.20.0.2

Default credentials: `ansible:ansible` (SSH key preferred)

## Persistent Testing Workflow

Keep containers running while iterating:

```bash
# Start once
./test-runner.sh start

# Edit playbooks in ../
# Then test changes:
./test-runner.sh preflight
./test-runner.sh dryrun

# Repeat as needed...

# Stop when done
./test-runner.sh stop
```

## Troubleshooting

```bash
# Check container logs
docker logs posix-hardening-target1
docker logs posix-hardening-controller

# Check running containers
docker ps

# Restart everything
./test-runner.sh clean
./test-runner.sh start

# Test SSH from host (if needed)
ssh -i testing/ssh_keys/id_rsa -p 2201 ansible@localhost
```

## Requirements

- Docker and Docker Compose
- 4GB+ RAM
- 10GB free disk space

See [README.md](README.md) for complete documentation.
