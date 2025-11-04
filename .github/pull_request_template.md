## Summary

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

- [ ] Bug fix (fixes an issue without breaking existing functionality)
- [ ] New feature (adds functionality without breaking existing features)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Code refactoring (no functional changes)
- [ ] Performance improvement
- [ ] Security fix

## Related Issues

<!-- Link to related issues using #issue_number -->
Fixes #
Relates to #

## Changes Made

<!-- Describe the changes in detail -->

### Modified Files
-
-
-

### New Files
-
-

## Testing

### Test Environment
- [ ] Tested in Docker container
- [ ] Tested on Debian 11
- [ ] Tested on Debian 12
- [ ] Tested on Ubuntu 20.04
- [ ] Tested on Ubuntu 22.04
- [ ] Other: <!-- specify -->

### Test Results
- [ ] Dry-run mode verified (`DRY_RUN=1`)
- [ ] Scripts maintain SSH access throughout execution
- [ ] Rollback tested and functional
- [ ] No errors in `/var/log/hardening/`
- [ ] Validation suite passes (`tests/validation_suite.sh`)
- [ ] POSIX compliance verified (tested with dash/ash)

### Shell Compatibility
- [ ] Tested with `/bin/sh`
- [ ] Tested with `dash`
- [ ] Tested with `bash`
- [ ] No bashisms detected (`checkbashisms` clean)
- [ ] ShellCheck passes with no errors

## Checklist

### Code Quality
- [ ] Code follows POSIX sh standards (no bash-specific features)
- [ ] Scripts are idempotent (can be run multiple times safely)
- [ ] All functions have error handling
- [ ] Proper quoting used for all variables
- [ ] No hardcoded values (uses configuration variables)

### Safety
- [ ] Backups are created before modifications
- [ ] SSH access is preserved throughout
- [ ] Rollback functionality works correctly
- [ ] Safety checks are not bypassed
- [ ] Emergency access methods remain functional

### Security
- [ ] No sensitive data committed (passwords, keys, tokens)
- [ ] No security vulnerabilities introduced
- [ ] Firewall rules reviewed and validated
- [ ] SSH configuration changes are secure
- [ ] File permissions are appropriate

### Documentation
- [ ] Code is well-commented
- [ ] README updated (if applicable)
- [ ] CHANGELOG.md updated
- [ ] Script documentation updated (`docs/SCRIPTS.md`)
- [ ] Configuration variables documented

### Ansible (if applicable)
- [ ] `ansible-lint` passes with no errors
- [ ] Playbooks are idempotent
- [ ] Variables are defined in `group_vars/all.yml`
- [ ] Templates are properly formatted
- [ ] Tasks use appropriate Ansible modules (not excessive shell commands)

## Breaking Changes

<!-- If this PR includes breaking changes, describe them here and provide migration instructions -->

## Additional Notes

<!-- Any additional information that reviewers should know -->

## Screenshots / Logs

<!-- If applicable, add screenshots or relevant log excerpts -->

```
# Paste relevant logs here
```

## Reviewer Focus Areas

<!-- Highlight specific areas where you'd like focused review -->

-
-
-

---

**I confirm that:**
- [ ] This code has been tested in a safe environment
- [ ] All tests pass successfully
- [ ] Documentation has been updated
- [ ] No sensitive information is included
- [ ] This PR follows the project's contribution guidelines
