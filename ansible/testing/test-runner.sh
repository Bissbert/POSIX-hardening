#!/bin/sh
# POSIX Hardening - Docker-based Ansible Testing Script
# Automates the complete testing workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY_DIR="$SCRIPT_DIR/ssh_keys"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Generate SSH keys if they don't exist
generate_ssh_keys() {
    log_info "Checking SSH keys..."

    if [ ! -d "$SSH_KEY_DIR" ]; then
        mkdir -p "$SSH_KEY_DIR"
    fi

    if [ ! -f "$SSH_KEY_DIR/id_rsa" ]; then
        log_info "Generating SSH key pair for testing..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/id_rsa" -N "" -C "ansible-testing"
        chmod 600 "$SSH_KEY_DIR/id_rsa"
        chmod 644 "$SSH_KEY_DIR/id_rsa.pub"
        log_success "SSH keys generated"
    else
        log_success "SSH keys already exist"
    fi

    # Create authorized_keys file
    cp "$SSH_KEY_DIR/id_rsa.pub" "$SCRIPT_DIR/authorized_keys"
    chmod 644 "$SCRIPT_DIR/authorized_keys"
}

# Start Docker containers
start_containers() {
    log_info "Starting Docker containers..."
    cd "$SCRIPT_DIR"
    docker-compose up -d
    log_success "Containers started"

    log_info "Waiting for containers to be ready..."
    sleep 10
}

# Stop Docker containers
stop_containers() {
    log_info "Stopping Docker containers..."
    cd "$SCRIPT_DIR"
    docker-compose down
    log_success "Containers stopped"
}

# Clean up everything
cleanup() {
    log_info "Cleaning up Docker resources..."
    cd "$SCRIPT_DIR"
    docker-compose down -v
    log_success "Cleanup complete"
}

# Test SSH connectivity
test_ssh() {
    log_info "Testing SSH connectivity to containers..."

    if docker exec posix-hardening-controller \
        ssh -i /root/.ssh/id_rsa \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        ansible@172.20.0.10 "echo 'SSH to target1 OK'" >/dev/null 2>&1; then
        log_success "SSH connection to target1 successful"
    else
        log_error "SSH connection to target1 failed"
        return 1
    fi

    if docker exec posix-hardening-controller \
        ssh -i /root/.ssh/id_rsa \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        ansible@172.20.0.11 "echo 'SSH to target2 OK'" >/dev/null 2>&1; then
        log_success "SSH connection to target2 successful"
    else
        log_error "SSH connection to target2 failed"
        return 1
    fi
}

# Run preflight checks
run_preflight() {
    log_info "Running preflight checks..."

    docker exec posix-hardening-controller \
        ansible-playbook -i inventory-docker.ini preflight.yml

    log_success "Preflight checks completed"
}

# Run hardening in dry-run mode
run_dryrun() {
    log_info "Running hardening in dry-run mode..."

    docker exec posix-hardening-controller \
        ansible-playbook -i inventory-docker.ini site.yml \
        -e "dry_run=1" \
        --tags "deploy,priority1"

    log_success "Dry-run completed"
}

# Run full hardening
run_hardening() {
    log_info "Running full hardening playbook..."

    docker exec posix-hardening-controller \
        ansible-playbook -i inventory-docker.ini site.yml \
        -e "dry_run=0 run_full_hardening=true"

    log_success "Full hardening completed"
}

# Run validation
run_validation() {
    log_info "Running validation tests..."

    docker exec posix-hardening-controller \
        ansible-playbook -i inventory-docker.ini site.yml \
        --tags "validate"

    log_success "Validation completed"
}

# Display help
show_help() {
    cat <<EOF
POSIX Hardening - Docker Testing Script

Usage: $0 [COMMAND]

Commands:
    setup       Generate SSH keys and prepare environment
    start       Start Docker containers
    stop        Stop Docker containers
    clean       Stop containers and remove volumes
    ssh-test    Test SSH connectivity to containers
    preflight   Run preflight checks
    dryrun      Run hardening in dry-run mode (Priority 1 only)
    harden      Run full hardening playbook
    validate    Run validation tests
    full        Complete test cycle (setup, start, preflight, harden, validate)
    help        Show this help message

Examples:
    # Quick start - run complete test
    $0 full

    # Step by step testing
    $0 setup
    $0 start
    $0 ssh-test
    $0 preflight
    $0 dryrun
    $0 harden
    $0 validate
    $0 stop

    # Clean up after testing
    $0 clean

EOF
}

# Main command router
main() {
    case "${1:-help}" in
        setup)
            generate_ssh_keys
            ;;
        start)
            generate_ssh_keys
            start_containers
            ;;
        stop)
            stop_containers
            ;;
        clean)
            cleanup
            ;;
        ssh-test)
            test_ssh
            ;;
        preflight)
            run_preflight
            ;;
        dryrun)
            run_dryrun
            ;;
        harden)
            run_hardening
            ;;
        validate)
            run_validation
            ;;
        full)
            log_info "Starting complete test cycle..."
            generate_ssh_keys
            start_containers
            test_ssh
            run_preflight
            run_dryrun
            log_warning "Dry-run completed. Review output before proceeding."
            printf "Continue with full hardening? [y/N] "
            read -r answer
            if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
                run_hardening
                run_validation
                log_success "Complete test cycle finished!"
            else
                log_info "Skipping full hardening. Containers are still running."
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
