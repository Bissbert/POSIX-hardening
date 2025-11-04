# Molecule Tests for SSH Hardening Role

This directory contains Molecule tests for the `posix_hardening_ssh` role.

## Quick Start

```bash
# Run full test suite
molecule test

# Development workflow
molecule create    # Create container
molecule converge  # Apply role
molecule verify    # Run tests
molecule destroy   # Clean up
```

## Test Scenarios

### Default Scenario

Location: `molecule/default/`

Tests the SSH hardening role with:

- **Platform**: Ubuntu 22.04 (Docker container)
- **Test User**: adminuser (with SSH keys)
- **Admin IP**: 192.168.1.100 (simulated)
- **Emergency Port**: 2222 (enabled)

### Test Coverage

The default scenario includes 26 tests covering:

- ✅ SSH configuration files and permissions
- ✅ Security settings (no root login, no password auth)
- ✅ Service status and port listening
- ✅ SSH banner configuration
- ✅ Configuration validation
- ✅ Additional security hardening

**Current Results**: 22/26 tests passing (85%)

Known failures in containerized environments:

- Drift detection markers (ephemeral filesystem)
- Backup verification (container limitations)

## File Structure

```text
molecule/
└── default/                 # Default test scenario
    ├── molecule.yml         # Molecule configuration
    ├── prepare.yml          # Test environment setup
    ├── converge.yml         # Apply SSH role
    ├── pytest.ini           # Pytest configuration
    ├── tests/
    │   └── test_default.py  # TestInfra test suite
    └── roles/               # Symlink to role (gitignored)
        └── posix_hardening_ssh -> ../../../
```

## Configuration

### molecule.yml

Key settings:

- **Driver**: Docker
- **Platform**: geerlingguy/docker-ubuntu2204-ansible:latest
- **Provisioner**: Ansible
- **Verifier**: TestInfra (pytest)

### Test Variables

Configured in `molecule.yml` inventory:

```yaml
ansible_user: root
admin_ip: "192.168.1.100"
posix_ssh_allow_users:
  - adminuser
  - root
posix_ssh_permit_root_login: "no"
posix_ssh_password_authentication: false
posix_ssh_pubkey_authentication: true
posix_ssh_emergency_port_enabled: true
posix_ssh_emergency_port: 2222
posix_ssh_skip_connectivity_test: true  # Container limitation
```

## Running Tests

### Full Test Suite

```bash
molecule test
```

Runs complete test sequence:

1. Dependency
2. Cleanup
3. Destroy
4. Syntax
5. Create
6. Prepare
7. Converge
8. Idempotence
9. Verify
10. Cleanup
11. Destroy

### Individual Phases

```bash
# Validate syntax
molecule syntax

# Create test container
molecule create

# Setup test environment
molecule prepare

# Apply SSH hardening role
molecule converge

# Run verification tests
molecule verify

# Check idempotence
molecule idempotence

# Clean up
molecule destroy
```

### Specific Tests

```bash
# Run specific test class
pytest tests/test_default.py::TestSSHSecuritySettings -v

# Run single test
pytest tests/test_default.py::TestSSHSecuritySettings::test_root_login_disabled -v

# Run by marker
pytest tests/test_default.py -m ssh -v
```

## Development Workflow

For rapid iteration during role development:

```bash
# 1. Initial setup (once)
molecule create

# 2. Edit role files
vim ../../tasks/main.yml

# 3. Test changes (repeat)
molecule converge  # Apply changes
molecule verify    # Run tests

# 4. Cleanup when done
molecule destroy
```

## Adding New Tests

Edit `tests/test_default.py`:

```python
class TestNewFeature:
    """Test new SSH feature."""

    def test_new_configuration(self, host):
        """Verify new configuration is applied."""
        config = host.file("/etc/ssh/sshd_config")
        assert "NewSetting yes" in config.content_string
```

Run tests:

```bash
molecule verify
```

## Troubleshooting

### Container Won't Start

```bash
# Clean up
docker ps -a | grep molecule
docker rm -f $(docker ps -aq) || true
docker network prune -f

# Try again
molecule destroy
molecule create
```

### Tests Fail

```bash
# Debug mode
molecule --debug verify

# Check container
docker ps
docker logs ssh-test-target

# SSH into container
docker exec -it ssh-test-target bash
```

### Ansible Collection Missing

```bash
ansible-galaxy collection install community.docker ansible.posix --force
```

## CI/CD Integration

These tests run automatically in GitHub Actions on:

- Push to main
- Pull requests
- Changes to SSH role files

Workflow: `.github/workflows/molecule-test.yml`

## More Information

See: [../../TESTING.md](../../TESTING.md)
