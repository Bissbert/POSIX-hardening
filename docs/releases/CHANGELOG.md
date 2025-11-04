# Changelog

All notable changes to the POSIX Shell Server Hardening Toolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-17

### Added

- Initial release of POSIX Shell Server Hardening Toolkit
- 20 individual hardening scripts covering:
  - SSH hardening with connection preservation
  - Firewall configuration with safety mechanisms
  - Kernel parameter hardening
  - Network stack hardening
  - System permissions and file integrity
  - Service hardening and audit configuration
  - Password policies and authentication
  - Log rotation and system cleanup
- Core safety libraries:
  - `common.sh` - Logging, validation, and utilities
  - `ssh_safety.sh` - SSH connection preservation
  - `backup.sh` - Comprehensive backup system
  - `rollback.sh` - Transaction-based rollback mechanisms
- Orchestrator script for automated execution
- Emergency rollback system with multiple recovery options
- Comprehensive validation suite with 30+ tests
- Ansible automation for multi-server deployment:
  - Pre-flight checks
  - Priority-based deployment
  - Emergency rollback playbook
  - Dry-run mode support
- Full POSIX shell compliance (sh, not bash)
- Automatic 60-second SSH rollback on connection loss
- Emergency SSH access on port 2222
- Transaction-based operations with automatic rollback
- Idempotent script execution
- Comprehensive documentation and examples

### Security Features

- Never loses SSH access during hardening
- Automatic rollback on configuration errors
- Firewall rules with 5-minute safety timers
- Multiple backup points before changes
- Emergency recovery mechanisms
- Safe remote execution support

### Compatibility

- Debian/Ubuntu systems
- POSIX-compliant shell (sh)
- Ansible 2.9+
- Python 3.6+

## [Unreleased]

### To Do

- Add support for RedHat/CentOS systems
- Implement CIS benchmark compliance checking
- Add automated security scanning integration
- Create web-based management interface
- Add Docker container support
- Implement centralized logging integration
