#!/usr/bin/env bash
# ==============================================================================
# Week 2 Implementation Verification Script
# ==============================================================================
# Verifies that all Week 2 roles are properly implemented and valid
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

echo "=========================================="
echo "Week 2 Verification Script"
echo "=========================================="
echo "Project Root: ${PROJECT_ROOT}"
echo "Ansible Dir:  ${ANSIBLE_DIR}"
echo ""

cd "${ANSIBLE_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Function to check file exists
check_file() {
    local file="$1"
    local description="$2"

    if [ -f "${file}" ]; then
        echo -e "${GREEN}✓${NC} ${description}"
        return 0
    else
        echo -e "${RED}✗${NC} ${description} (NOT FOUND: ${file})"
        ((ERRORS++))
        return 1
    fi
}

# Function to validate YAML
validate_yaml() {
    local file="$1"
    local description="$2"

    if python3 -c "import yaml; yaml.safe_load(open('${file}'))" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ${description}"
        return 0
    else
        echo -e "${RED}✗${NC} ${description} (INVALID YAML)"
        ((ERRORS++))
        return 1
    fi
}

echo "=========================================="
echo "1. Checking Role Structure"
echo "=========================================="

# posix_hardening_validation
check_file "roles/posix_hardening_validation/tasks/main.yml" "Validation role tasks"
check_file "roles/posix_hardening_validation/defaults/main.yml" "Validation role defaults"
check_file "roles/posix_hardening_validation/meta/main.yml" "Validation role meta"

# posix_hardening_deploy
check_file "roles/posix_hardening_deploy/tasks/main.yml" "Deploy role tasks"
check_file "roles/posix_hardening_deploy/defaults/main.yml" "Deploy role defaults"
check_file "roles/posix_hardening_deploy/meta/main.yml" "Deploy role meta"
check_file "roles/posix_hardening_deploy/templates/defaults.conf.j2" "Deploy role template"

# posix_hardening_users
check_file "roles/posix_hardening_users/tasks/main.yml" "Users role tasks"
check_file "roles/posix_hardening_users/tasks/create_users.yml" "Users role create_users"
check_file "roles/posix_hardening_users/tasks/deploy_keys.yml" "Users role deploy_keys"
check_file "roles/posix_hardening_users/defaults/main.yml" "Users role defaults"
check_file "roles/posix_hardening_users/meta/main.yml" "Users role meta"
check_file "roles/posix_hardening_users/templates/sudoers.j2" "Users role sudoers template"

# Test playbook
check_file "playbooks/test_week2_roles.yml" "Week 2 test playbook"

echo ""
echo "=========================================="
echo "2. Validating YAML Syntax"
echo "=========================================="

validate_yaml "roles/posix_hardening_validation/tasks/main.yml" "Validation tasks YAML"
validate_yaml "roles/posix_hardening_validation/defaults/main.yml" "Validation defaults YAML"
validate_yaml "roles/posix_hardening_validation/meta/main.yml" "Validation meta YAML"

validate_yaml "roles/posix_hardening_deploy/tasks/main.yml" "Deploy tasks YAML"
validate_yaml "roles/posix_hardening_deploy/defaults/main.yml" "Deploy defaults YAML"
validate_yaml "roles/posix_hardening_deploy/meta/main.yml" "Deploy meta YAML"

validate_yaml "roles/posix_hardening_users/tasks/main.yml" "Users main tasks YAML"
validate_yaml "roles/posix_hardening_users/tasks/create_users.yml" "Users create_users YAML"
validate_yaml "roles/posix_hardening_users/tasks/deploy_keys.yml" "Users deploy_keys YAML"
validate_yaml "roles/posix_hardening_users/defaults/main.yml" "Users defaults YAML"
validate_yaml "roles/posix_hardening_users/meta/main.yml" "Users meta YAML"

validate_yaml "playbooks/test_week2_roles.yml" "Test playbook YAML"

echo ""
echo "=========================================="
echo "3. Checking Source Files Exist"
echo "=========================================="

# Check lib files
if [ -d "../lib" ]; then
    echo -e "${GREEN}✓${NC} lib/ directory exists"
    lib_count=$(find ../lib -name "*.sh" -type f | wc -l | tr -d ' ')
    echo "  Found ${lib_count} library files"
else
    echo -e "${RED}✗${NC} lib/ directory NOT FOUND"
    ((ERRORS++))
fi

# Check scripts files
if [ -d "../scripts" ]; then
    echo -e "${GREEN}✓${NC} scripts/ directory exists"
    script_count=$(find ../scripts -name "*.sh" -type f | wc -l | tr -d ' ')
    echo "  Found ${script_count} script files"
else
    echo -e "${RED}✗${NC} scripts/ directory NOT FOUND"
    ((ERRORS++))
fi

# Check tests files
if [ -d "../tests" ]; then
    echo -e "${GREEN}✓${NC} tests/ directory exists"
    test_count=$(find ../tests -name "*.sh" -type f | wc -l | tr -d ' ')
    echo "  Found ${test_count} test files"
else
    echo -e "${YELLOW}⚠${NC} tests/ directory not found (optional)"
    ((WARNINGS++))
fi

echo ""
echo "=========================================="
echo "4. Checking Variable Definitions"
echo "=========================================="

if [ -f "group_vars/all.yml" ]; then
    echo -e "${GREEN}✓${NC} group_vars/all.yml exists"

    # Check for required variables
    required_vars=(
        "admin_ip"
        "ssh_allow_users"
        "ssh_port"
        "toolkit_path"
        "backup_path"
        "log_path"
        "state_path"
    )

    for var in "${required_vars[@]}"; do
        if grep -q "^${var}:" group_vars/all.yml 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Variable defined: ${var}"
        else
            echo -e "${RED}✗${NC} Variable NOT defined: ${var}"
            ((ERRORS++))
        fi
    done
else
    echo -e "${RED}✗${NC} group_vars/all.yml NOT FOUND"
    ((ERRORS++))
fi

echo ""
echo "=========================================="
echo "5. Checking Ansible Configuration"
echo "=========================================="

if [ -f "ansible.cfg" ]; then
    echo -e "${GREEN}✓${NC} ansible.cfg exists"
else
    echo -e "${YELLOW}⚠${NC} ansible.cfg not found"
    ((WARNINGS++))
fi

echo ""
echo "=========================================="
echo "6. Code Statistics"
echo "=========================================="

total_lines=$(find roles/posix_hardening_{validation,deploy,users} -name "*.yml" -type f -exec wc -l {} + | tail -1 | awk '{print $1}')
playbook_lines=$(wc -l playbooks/test_week2_roles.yml 2>/dev/null | awk '{print $1}')
total_with_playbook=$((total_lines + playbook_lines))

echo "Role YAML files:       ${total_lines} lines"
echo "Test playbook:         ${playbook_lines} lines"
echo "Total implementation:  ${total_with_playbook} lines"

echo ""
echo "=========================================="
echo "7. Summary"
echo "=========================================="

if [ ${ERRORS} -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    if [ ${WARNINGS} -gt 0 ]; then
        echo -e "${YELLOW}⚠ ${WARNINGS} warning(s)${NC}"
    fi
    echo ""
    echo "Week 2 roles are ready for testing."
    echo ""
    echo "Next steps:"
    echo "  1. Run syntax check:"
    echo "     ansible-playbook playbooks/test_week2_roles.yml --syntax-check"
    echo ""
    echo "  2. Run in check mode:"
    echo "     ansible-playbook playbooks/test_week2_roles.yml --check --limit testing"
    echo ""
    echo "  3. Test on docker/VM:"
    echo "     ansible-playbook playbooks/test_week2_roles.yml --limit docker_test1"
    exit 0
else
    echo -e "${RED}✗ ${ERRORS} error(s) found${NC}"
    if [ ${WARNINGS} -gt 0 ]; then
        echo -e "${YELLOW}⚠ ${WARNINGS} warning(s)${NC}"
    fi
    echo ""
    echo "Fix errors before proceeding."
    exit 1
fi
