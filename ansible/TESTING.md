# POSIX Hardening - Testing Guide

This guide explains how to test the Ansible roles using Molecule and TestInfra.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Local Testing](#local-testing)
- [Understanding Test Results](#understanding-test-results)
- [Writing New Tests](#writing-new-tests)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Overview

We use **Molecule** as our testing framework, combined with:

- **Docker** - Test environment driver
- **TestInfra** - Infrastructure testing framework (pytest-based)
- **Ansible** - Configuration management

### What Gets Tested

- SSH hardening configuration
- Firewall rules and safety mechanisms
- Security settings and compliance
- Service configuration and status
- File permissions and ownership

### Test Coverage

Currently implemented:

- ✅ SSH Hardening Role - 26 tests (85% pass rate)
- ⏳ Firewall Hardening Role - Tests planned

## Prerequisites

### Required Software

1. **Python 3.11+**

   ```bash
   python3 --version
   ```

2. **Docker**

   ```bash
   docker --version
   ```

3. **Git**

   ```bash
   git --version
   ```

### Installation

Install testing dependencies:

```bash
# From the repository root
pip install -r ansible/requirements-dev.txt

# Install required Ansible collections
ansible-galaxy collection install community.docker ansible.posix --force
```

Verify Molecule is installed:

```bash
molecule --version
```

Expected output:

```text
molecule 25.9.0 using python 3.11
    ansible:2.19.3
    docker:25.8.12 from molecule_plugins requiring collections: community.docker>=3.10.2 ansible.posix>=1.4.0
```

## Local Testing

### Quick Test - Single Role

Test the SSH hardening role:

```bash
cd ansible/roles/posix_hardening_ssh
molecule test
```

This runs the full test sequence:

1. Dependency - Install role dependencies
2. Cleanup - Remove old test artifacts
3. Destroy - Remove old containers
4. Syntax - Validate Ansible syntax
5. Create - Start Docker test container
6. Prepare - Setup test environment
7. Converge - Apply the role
8. Idempotence - Verify role is idempotent
9. Verify - Run TestInfra tests
10. Cleanup - Remove test artifacts
11. Destroy - Remove containers

### Selective Testing

Run only specific test phases:

```bash
# Syntax check only
molecule syntax

# Create container and prepare
molecule create

# Apply role configuration
molecule converge

# Run verification tests
molecule verify

# Clean up
molecule destroy
```

### Development Workflow

For rapid testing during development:

```bash
# 1. Create and prepare test environment (one time)
molecule create

# 2. Apply role and test (repeat as needed)
molecule converge
molecule verify

# 3. Cleanup when done
molecule destroy
```

### Running Specific Tests

Run individual test classes or methods:

```bash
cd ansible/roles/posix_hardening_ssh

# Run specific test class
pytest molecule/default/tests/test_default.py::TestSSHSecuritySettings -v

# Run specific test method
pytest molecule/default/tests/test_default.py::TestSSHSecuritySettings::test_root_login_disabled -v

# Run tests by marker
pytest molecule/default/tests/test_default.py -m ssh -v
```

## Understanding Test Results

### Test Output

Molecule provides detailed output:

```text
============================= test session starts ==============================
tests/test_default.py::TestSSHConfigurationFiles::test_sshd_config_exists PASSED
tests/test_default.py::TestSSHSecuritySettings::test_root_login_disabled PASSED
...
===================== 22 passed, 4 failed, 3 warnings in 4.27s =================
```

### Test Categories

Tests are organized into classes by functionality:

- **TestSSHConfigurationFiles** - File existence and permissions
- **TestSSHSecuritySettings** - Security configuration values
- **TestSSHService** - Service status and ports
- **TestSSHBanner** - Banner configuration
- **TestSSHDriftDetection** - Configuration drift detection
- **TestSSHBackupMechanism** - Backup file creation
- **TestSSHConfigValidation** - Config syntax validation
- **TestSSHSecurityHardening** - Additional security settings

### Known Test Failures

Some tests may fail in containerized environments:

- **Drift detection marker** - Container ephemeral filesystem
- **Backup creation** - Skip in container testing
- **Connectivity validation** - Requires network routing

These are expected and don't indicate role failures. The critical security tests all pass.

## Writing New Tests

### Test Structure

Tests use pytest and TestInfra:

```python
class TestNewFeature:
    """Test description."""

    def test_configuration_applied(self, host):
        """Verify configuration is applied correctly."""
        # Get file handle
        f = host.file("/path/to/config")

        # Assert conditions
        assert f.exists
        assert f.user == "root"
        assert f.mode == 0o600

        # Check content
        content = f.content_string
        assert "ExpectedSetting yes" in content
```

### TestInfra API

Common test operations:

```python
# File operations
f = host.file("/path/to/file")
assert f.exists
assert f.is_file
assert f.user == "root"
assert f.group == "root"
assert f.mode == 0o644
content = f.content_string

# Service operations
s = host.service("sshd")
assert s.is_running
assert s.is_enabled

# Socket/Port operations
sock = host.socket("tcp://0.0.0.0:22")
assert sock.is_listening

# Command execution
cmd = host.run("sshd -t")
assert cmd.rc == 0
assert "error" not in cmd.stderr.lower()

# Package operations
pkg = host.package("openssh-server")
assert pkg.is_installed
```

### Adding Tests to Existing Roles

1. **Edit test file**: `molecule/default/tests/test_default.py`
2. **Add new test class or method**
3. **Run tests**: `molecule verify`
4. **Iterate until passing**

### Creating Tests for New Roles

When adding Molecule tests to a new role:

```bash
# Navigate to role
cd ansible/roles/your_new_role

# Create Molecule scenario
mkdir -p molecule/default/tests

# Create symlink to role
mkdir -p molecule/default/roles
ln -s ../../../ molecule/default/roles/your_new_role
```

Copy and adapt files from `posix_hardening_ssh`:

- `molecule.yml` - Molecule configuration
- `prepare.yml` - Test environment setup
- `converge.yml` - Role application
- `tests/test_default.py` - Test definitions
- `pytest.ini` - Pytest configuration

Update `.gitignore`:

```bash
# Already configured for all roles
ansible/roles/**/molecule/**/roles/
```

## CI/CD Integration

### GitHub Actions

The Molecule tests run automatically on GitHub Actions:

**Workflow**: `.github/workflows/molecule-test.yml`

**Triggers**:

- Push to main branch
- Pull requests to main
- Changes to role files or test configs

**Path Filters**:

```yaml
paths:
  - 'ansible/roles/posix_hardening_ssh/**'
  - 'ansible/roles/posix_hardening_firewall/**'
  - 'ansible/requirements*.txt'
  - '.github/workflows/molecule-test.yml'
```

### Viewing CI Results

1. Go to repository on GitHub
2. Click **Actions** tab
3. Select **Molecule Testing** workflow
4. View test results and logs

### Artifacts

Test results are uploaded as artifacts (retained for 7 days):

- Molecule logs
- Test output
- Container logs (on failure)

Download from GitHub Actions workflow run page.

## Troubleshooting

### Docker Permission Errors

**Problem**: `permission denied while trying to connect to the Docker daemon socket`

**Solution**:

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login, or:
newgrp docker

# Verify
docker ps
```

### Molecule Container Creation Fails

**Problem**: `Error creating container`

**Solution**:

```bash
# Check Docker is running
docker ps

# Remove old containers
docker rm -f $(docker ps -aq) || true

# Clean Docker networks
docker network prune -f

# Try again
molecule destroy
molecule create
```

### Ansible Collection Not Found

**Problem**: `ERROR! couldn't resolve module/action 'community.docker.docker_container'`

**Solution**:

```bash
# Reinstall collections
ansible-galaxy collection install community.docker ansible.posix --force

# Verify installation
ansible-galaxy collection list
```

### Test Failures - Timeout

**Problem**: Tests fail with timeout errors

**Solution**:

```bash
# Increase timeout in molecule.yml
provisioner:
  config_options:
    defaults:
      timeout: 60  # Increase from default 30

# Or skip problematic tests
molecule verify -- -k 'not test_connectivity'
```

### Python Version Conflicts

**Problem**: `ModuleNotFoundError` or package conflicts

**Solution**:

```bash
# Use virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies fresh
pip install --upgrade pip
pip install -r ansible/requirements-dev.txt
```

### TestInfra Connection Issues

**Problem**: `ConnectionError` when running tests

**Solution**:

```bash
# Ensure container exists
docker ps -a | grep ssh-test-target

# Recreate if needed
molecule destroy
molecule create

# Check TestInfra can connect
docker exec ssh-test-target whoami
```

### Debugging Failed Tests

**Enable verbose output**:

```bash
# Molecule verbose
molecule --debug test

# Ansible verbose
molecule converge -- -vvv

# Pytest verbose
molecule verify -- -vvv --tb=long
```

**Check container logs**:

```bash
# SSH role container
docker logs ssh-test-target

# Execute commands in container
docker exec -it ssh-test-target bash
```

**Inspect test environment**:

```bash
# Keep container running after test
molecule test --destroy=never

# SSH into container
docker exec -it ssh-test-target bash

# Check configuration
cat /etc/ssh/sshd_config
systemctl status sshd
```

## Best Practices

### Test Organization

1. **Group related tests** into classes
2. **Use descriptive names** for test methods
3. **Add docstrings** explaining what is tested
4. **Use markers** for test categorization

### Test Reliability

1. **Avoid hardcoded values** - use variables from molecule.yml
2. **Handle container limitations** - skip tests that won't work in containers
3. **Test idempotence** - ensure roles can run multiple times safely
4. **Clean up after tests** - always destroy containers when done

### Performance

1. **Use `--destroy=never`** during development to keep containers
2. **Run specific tests** instead of full suite during iteration
3. **Parallelize tests** when testing multiple roles
4. **Cache Python packages** in CI/CD

## Additional Resources

- [Molecule Documentation](https://ansible.readthedocs.io/projects/molecule/)
- [TestInfra Documentation](https://testinfra.readthedocs.io/)
- [Ansible Testing Strategies](https://docs.ansible.com/ansible/latest/dev_guide/testing.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

## Getting Help

If you encounter issues not covered here:

1. Check the [GitHub Issues](https://github.com/Bissbert/POSIX-hardening/issues)
2. Review Molecule logs: `molecule/default/.molecule/*/ansible.log`
3. Enable debug mode: `molecule --debug test`
4. Open a new issue with full error output and steps to reproduce
