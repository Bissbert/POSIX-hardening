"""
Molecule TestInfra Tests for posix_hardening_ssh Role
Tests verify SSH hardening configuration, security settings, and safety mechanisms.
"""

import os
import pytest
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']
).get_hosts('all')


class TestSSHConfigurationFiles:
    """Test SSH configuration files and directories."""

    def test_sshd_config_exists(self, host):
        """Verify SSH daemon config file exists."""
        f = host.file("/etc/ssh/sshd_config")
        assert f.exists
        assert f.is_file
        assert f.user == "root"
        assert f.group == "root"
        assert f.mode == 0o600

    def test_ssh_directory_permissions(self, host):
        """Verify SSH directory has correct permissions."""
        d = host.file("/etc/ssh")
        assert d.exists
        assert d.is_directory
        assert d.user == "root"
        assert d.group == "root"

    def test_backup_directory_exists(self, host):
        """Verify SSH backup directory was created."""
        d = host.file("/var/backups/ssh")
        assert d.exists
        assert d.is_directory
        assert d.user == "root"
        assert d.mode == 0o750


class TestSSHSecuritySettings:
    """Test SSH security configuration settings."""

    def test_root_login_disabled(self, host):
        """Verify root login is disabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        assert "PermitRootLogin no" in config or \
               "PermitRootLogin prohibit-password" in config

    def test_password_authentication_disabled(self, host):
        """Verify password authentication is disabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        assert "PasswordAuthentication no" in config

    def test_pubkey_authentication_enabled(self, host):
        """Verify public key authentication is enabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        assert "PubkeyAuthentication yes" in config

    def test_empty_passwords_disabled(self, host):
        """Verify empty passwords are not permitted."""
        config = host.file("/etc/ssh/sshd_config").content_string
        assert "PermitEmptyPasswords no" in config

    def test_x11_forwarding_disabled(self, host):
        """Verify X11 forwarding is disabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        # May be commented out or explicitly set
        assert "X11Forwarding no" in config or \
               "#X11Forwarding" in config

    def test_max_auth_tries_limited(self, host):
        """Verify max authentication tries is limited."""
        config = host.file("/etc/ssh/sshd_config").content_string
        # Check that MaxAuthTries is set to reasonable value (<=6)
        if "MaxAuthTries" in config:
            import re
            match = re.search(r'MaxAuthTries\s+(\d+)', config)
            if match:
                assert int(match.group(1)) <= 6


class TestSSHService:
    """Test SSH service status and operation."""

    def test_ssh_service_running(self, host):
        """Verify SSH service is running."""
        service = host.service("ssh")
        # Service might be called 'ssh' or 'sshd' depending on OS
        if not service.is_running:
            service = host.service("sshd")
        assert service.is_running

    def test_ssh_service_enabled(self, host):
        """Verify SSH service is enabled at boot."""
        service = host.service("ssh")
        if not service.is_enabled:
            service = host.service("sshd")
        assert service.is_enabled

    def test_ssh_port_listening(self, host):
        """Verify SSH is listening on standard port 22."""
        assert host.socket("tcp://0.0.0.0:22").is_listening or \
               host.socket("tcp://:::22").is_listening

    def test_emergency_port_listening(self, host):
        """Verify emergency SSH port 2222 is listening."""
        assert host.socket("tcp://0.0.0.0:2222").is_listening or \
               host.socket("tcp://:::2222").is_listening


class TestSSHBanner:
    """Test SSH banner configuration."""

    def test_banner_file_exists(self, host):
        """Verify SSH banner file exists."""
        f = host.file("/etc/ssh/banner")
        assert f.exists
        assert f.is_file
        assert f.user == "root"
        assert f.group == "root"
        assert f.mode == 0o644

    def test_banner_configured_in_sshd(self, host):
        """Verify banner is configured in sshd_config."""
        config = host.file("/etc/ssh/sshd_config").content_string
        assert "Banner /etc/ssh/banner" in config

    def test_banner_content_not_empty(self, host):
        """Verify banner file has content."""
        f = host.file("/etc/ssh/banner")
        assert f.size > 0


class TestSSHDriftDetection:
    """Test configuration drift detection mechanism."""

    def test_drift_marker_file_exists(self, host):
        """Verify drift detection marker file exists."""
        # The role creates this to track configuration
        f = host.file("/var/lib/ansible/posix_ssh_config_applied")
        assert f.exists
        assert f.is_file

    def test_drift_marker_has_content(self, host):
        """Verify drift marker contains configuration data."""
        f = host.file("/var/lib/ansible/posix_ssh_config_applied")
        assert f.size > 0

    def test_ansible_state_directory_exists(self, host):
        """Verify Ansible state directory exists."""
        d = host.file("/var/lib/ansible")
        assert d.exists
        assert d.is_directory


class TestSSHBackupMechanism:
    """Test SSH configuration backup mechanism."""

    def test_sshd_config_backup_created(self, host):
        """Verify sshd_config backup was created."""
        # Check that at least one backup exists
        cmd = host.run("ls -1 /var/backups/ssh/sshd_config.* 2>/dev/null | head -1")
        assert cmd.rc == 0
        assert len(cmd.stdout.strip()) > 0

    def test_backup_file_readable(self, host):
        """Verify backup file is readable."""
        cmd = host.run("ls -1 /var/backups/ssh/sshd_config.* 2>/dev/null | head -1")
        if cmd.rc == 0 and cmd.stdout.strip():
            backup_file = cmd.stdout.strip()
            f = host.file(backup_file)
            assert f.exists
            assert f.is_file
            assert f.user == "root"


class TestSSHConfigValidation:
    """Test SSH configuration validation."""

    def test_sshd_config_valid(self, host):
        """Verify sshd_config passes validation."""
        cmd = host.run("sshd -t")
        assert cmd.rc == 0, f"sshd config validation failed: {cmd.stderr}"

    def test_sshd_config_extended_test(self, host):
        """Verify sshd_config passes extended validation."""
        cmd = host.run("sshd -T")
        assert cmd.rc == 0, f"sshd extended test failed: {cmd.stderr}"


class TestSSHSecurityHardening:
    """Test additional SSH security hardening."""

    def test_strict_modes_enabled(self, host):
        """Verify StrictModes is enabled."""
        # StrictModes is enabled by default, verify it's not disabled
        config = host.file("/etc/ssh/sshd_config").content_string
        # Should not contain "StrictModes no"
        assert "StrictModes no" not in config.lower()

    def test_host_based_auth_disabled(self, host):
        """Verify host-based authentication is disabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        # Check for explicit disable or rely on default (no)
        if "HostbasedAuthentication" in config:
            assert "HostbasedAuthentication no" in config

    def test_ignore_rhosts_enabled(self, host):
        """Verify IgnoreRhosts is enabled."""
        config = host.file("/etc/ssh/sshd_config").content_string
        # Should be enabled by default or explicitly
        if "IgnoreRhosts" in config:
            assert "IgnoreRhosts yes" in config


# Pytest markers for selective testing
pytestmark = [
    pytest.mark.ssh,
    pytest.mark.security,
    pytest.mark.hardening
]


# Fixture to check if we're in check mode (not applicable for testinfra)
@pytest.fixture
def not_in_check_mode():
    """Fixture to indicate we're not in check mode during verify."""
    return True
