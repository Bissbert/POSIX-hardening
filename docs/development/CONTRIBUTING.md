# Contributing to POSIX Shell Server Hardening Toolkit

Thank you for your interest in contributing to this security toolkit! We welcome
contributions that improve server security while maintaining our core principle:
**Never lose SSH access**.

## Code of Conduct

This project prioritizes:

1. **Safety** - Never lock administrators out of systems
2. **Security** - Improve system hardening without compromising access
3. **Simplicity** - Keep scripts small, focused, and POSIX-compliant
4. **Reliability** - All changes must be reversible

## How to Contribute

### Reporting Security Issues

**IMPORTANT**: If you discover a security vulnerability, please DO NOT open a public issue. Instead:

1. Email the maintainer directly with details
2. Include steps to reproduce if applicable
3. Allow time for a patch before public disclosure

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the issue template
3. Include:
   - System information (OS, shell version)
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant log output

### Suggesting Features

1. Open an issue with `[Feature Request]` prefix
2. Describe the security benefit
3. Explain how it maintains SSH access safety
4. Provide implementation ideas if possible

### Pull Requests

#### Before Starting

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Check existing issues/PRs to avoid duplicate work
4. For major changes, open an issue first to discuss

#### Development Guidelines

### POSIX Compliance

```shell
# Good - POSIX compliant
if [ -f "/etc/ssh/sshd_config" ]; then
    echo "File exists"
fi

# Bad - Bash-specific
if [[ -f /etc/ssh/sshd_config ]]; then
    echo "File exists"
fi
```

### Safety First

- Every script MUST preserve SSH access
- Include rollback mechanisms for risky changes
- Test on non-production systems first
- Add safety checks before destructive operations

### Script Structure

```shell
#!/bin/sh
# Script: XX-feature-name.sh
# Priority: [1-4]
# Description: Brief description

# Source safety libraries
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/ssh_safety.sh"

# Main logic with safety checks
main() {
    log "INFO" "Starting feature..."

    # Backup before changes
    backup_file "/etc/important.conf"

    # Make changes with error handling
    if ! apply_change; then
        rollback
        exit 1
    fi

    # Validate changes
    verify_change || rollback
}

main "$@"
```

#### Testing Requirements

1. **Manual Testing**
   - Test on fresh Debian/Ubuntu VM
   - Verify SSH access maintained
   - Test rollback mechanisms
   - Run validation suite

2. **Test Commands**

   ```shell
   # Run validation suite
   cd tests/
   sudo sh validation_suite.sh

   # Test specific script
   sudo sh scripts/XX-your-script.sh --test

   # Test with dry-run
   sudo sh orchestrator.sh --dry-run
   ```

3. **Ansible Testing**

   ```shell
   # Test deployment
   cd ansible/
   ansible-playbook site.yml -e "dry_run=1"
   ```

#### Commit Guidelines

### Commit Message Format

```text
type: brief description (max 50 chars)

Longer explanation if needed (wrap at 72 chars).
Explain the problem and solution.

Fixes: #issue-number (if applicable)
```

### Types

- `feat`: New hardening feature
- `fix`: Bug fix
- `sec`: Security improvement
- `docs`: Documentation only
- `test`: Test additions/fixes
- `ansible`: Ansible playbook changes
- `refactor`: Code restructuring

### Examples

```text
feat: add process accounting hardening

Implements process accounting to track system calls
and command execution. Includes safety checks to
prevent disk space issues.

Fixes: #42
```

#### Pull Request Process

1. **Update Documentation**
   - Update README if needed
   - Add script to documentation
   - Update CHANGELOG.md

2. **Ensure Quality**
   - Scripts are POSIX-compliant
   - No syntax errors: `sh -n script.sh`
   - Proper error handling
   - Rollback mechanisms work

3. **Submit PR**
   - Reference related issues
   - Describe changes clearly
   - Include test results
   - Note any breaking changes

4. **Review Process**
   - Maintainers will review for safety
   - May request changes or tests
   - Be responsive to feedback

### Adding New Hardening Scripts

New scripts should follow the naming convention:

```text
scripts/XX-feature-name.sh
```

Where XX is the priority number (01-99).

Required elements:

1. Safety checks (never lose SSH!)
2. Backup mechanisms
3. Rollback capability
4. Validation functions
5. Proper logging
6. POSIX compliance

Template for new scripts:

```shell
#!/bin/sh
# Script: XX-new-feature.sh
# Priority: X
# Description: What this hardens

set -e
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/backup.sh"

# Implementation with safety
```

### Documentation Standards

- Use clear, concise language
- Include examples for complex features
- Document all safety mechanisms
- Warn about any risks
- Keep README sections updated

### Questions?

Open an issue with `[Question]` prefix or check existing documentation:

- README.md - General usage
- ansible/README.md - Deployment guide
- docs/ - Additional documentation

## Recognition

Contributors will be added to AUTHORS.md file. Significant contributions may be highlighted in release notes.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.