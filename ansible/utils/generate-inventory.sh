#!/bin/sh
# ==============================================================================
# Automatic Inventory Generator
# ==============================================================================
# Discovers hosts via nmap and generates Ansible inventory files
# Usage: ./generate-inventory.sh [options]
#
# Debug mode: Set VERBOSE=1 environment variable for detailed output
# Example: VERBOSE=1 ./generate-inventory.sh --zone production
# ==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_FILE="$SCRIPT_DIR/inventory-config.yml"
TEMP_DIR="/tmp/inventory-gen-$$"

# Source libraries
. "$LIB_DIR/nmap-scanner.sh"
. "$LIB_DIR/service-detector.sh"
. "$LIB_DIR/inventory-builder.sh"

# Default values
INTERACTIVE=1
DRY_RUN=0
OUTPUT_FILE=""
ZONES=""
NO_CONFIRM=0

# =============================================================================
# Utilities
# =============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARNING: $*" >&2
}

# Simple YAML parser for our config
get_yaml_value() {
    local file="$1"
    local key="$2"

    grep "^${key}:" "$file" 2>/dev/null | head -1 | cut -d':' -f2- | sed 's/^[[:space:]]*//' | sed 's/"//g'
}

get_default_value() {
    local key="$1"

    awk -v key="$key" '
        /^defaults:/ { in_defaults=1; next }
        in_defaults && /^[a-z]/ { in_defaults=0 }
        in_defaults && $0 ~ "^  " key ":" {
            sub(/^[^:]*: */, "")
            gsub(/"/, "")
            print
            exit
        }
    ' "$CONFIG_FILE"
}

get_zone_value() {
    local zone="$1"
    local key="$2"

    awk -v zone="$zone" -v key="$key" '
        $0 ~ "^  " zone ":" { in_zone=1; next }
        in_zone && /^  [a-z]/ { in_zone=0 }
        in_zone && $0 ~ "^    " key ":" {
            sub(/^[^:]*: */, "")
            gsub(/"/, "")
            print
            exit
        }
    ' "$CONFIG_FILE"
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<EOF
Automatic Inventory Generator for POSIX Hardening Toolkit

USAGE:
    $0 [options]

OPTIONS:
    -i, --interactive       Interactive mode with prompts (default)
    -z, --zone ZONE        Scan specific zone(s) (comma-separated)
    -s, --subnet SUBNET    Override subnet for scanning
    -o, --output FILE      Output inventory file
    -d, --dry-run          Preview without scanning
    -y, --no-confirm       Skip confirmation prompts
    -h, --help             Show this help

EXAMPLES:
    # Interactive mode (default)
    $0 --interactive

    # Scan production zone only
    $0 --zone production

    # Scan multiple zones
    $0 --zone production,staging

    # Custom subnet and output
    $0 --zone test --subnet "10.0.0.0/24" --output custom-inventory.ini

    # Non-interactive for automation
    $0 --zone production --no-confirm

CONFIGURATION:
    Edit inventory-config.yml to configure:
    - Network zones and subnets
    - Ports to scan per zone
    - Service detection rules
    - Default Ansible variables

EOF
    exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--interactive)
                INTERACTIVE=1
                shift
                ;;
            -z|--zone)
                ZONES="$2"
                INTERACTIVE=0
                shift 2
                ;;
            -s|--subnet)
                CUSTOM_SUBNET="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -y|--no-confirm)
                NO_CONFIRM=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# =============================================================================
# Interactive Prompts
# =============================================================================

prompt_zones() {
    echo ""
    echo "=== Available Zones ==="
    echo "1) production - Production servers (full hardening)"
    echo "2) staging    - Staging servers (test first)"
    echo "3) test       - Test servers (dry-run mode)"
    echo "4) all        - Scan all zones"
    echo ""
    printf "Select zones to scan [1-4]: "
    read -r choice

    case "$choice" in
        1) ZONES="production" ;;
        2) ZONES="staging" ;;
        3) ZONES="test" ;;
        4) ZONES="production,staging,test" ;;
        *) error "Invalid choice" ;;
    esac
}

prompt_config() {
    echo ""
    echo "=== Configuration ==="

    # Get admin user
    printf "Ansible user [admin]: "
    read -r ansible_user
    ANSIBLE_USER="${ansible_user:-admin}"

    # Get SSH allowed users
    printf "SSH allowed users (space-separated) [$ANSIBLE_USER]: "
    read -r ssh_users
    SSH_ALLOW_USERS="${ssh_users:-$ANSIBLE_USER}"

    # Confirm scan
    if [ "$NO_CONFIRM" -eq 0 ]; then
        echo ""
        echo "Ready to scan zones: $ZONES"
        printf "Continue? [Y/n]: "
        read -r confirm
        case "$confirm" in
            [nN]*) exit 0 ;;
        esac
    fi
}

# =============================================================================
# Scanning
# =============================================================================

scan_zone() {
    local zone="$1"
    local subnet=$(get_zone_value "$zone" "subnet")
    local scan_ports=$(get_zone_value "$zone" "scan_ports")

    if [ -z "$subnet" ]; then
        warn "No subnet configured for zone: $zone"
        return 1
    fi

    # Validate scan_ports and provide fallback
    if [ -z "$scan_ports" ]; then
        warn "No scan_ports configured for zone: $zone, using defaults"
        scan_ports="22,80,443,3306,5432"
    fi

    log "Scanning zone: $zone ($subnet)"
    log "Ports to scan: $scan_ports"

    # Use custom subnet if provided
    if [ -n "$CUSTOM_SUBNET" ]; then
        subnet="$CUSTOM_SUBNET"
        log "Using custom subnet: $subnet"
    fi

    # Create temp directory for this zone
    local zone_dir="$TEMP_DIR/$zone"
    mkdir -p "$zone_dir"

    # Discover hosts
    log "Discovering hosts in $subnet..."
    if ! discover_hosts "$subnet" "$zone_dir/hosts.txt"; then
        warn "No hosts discovered in $zone"
        return 1
    fi

    local host_count=$(wc -l < "$zone_dir/hosts.txt")
    log "Found $host_count hosts in $zone"

    # Scan each host for open ports
    log "Scanning ports on discovered hosts..."
    while read -r host; do
        [ -z "$host" ] && continue

        log "  Scanning $host..."
        local open_ports=$(get_open_ports "$host" "$scan_ports" "basic")

        if [ -n "$open_ports" ]; then
            log "    Found ports: $open_ports"
            echo "$host|$open_ports" >> "$zone_dir/scan_results.txt"

            # Detect SSH port
            local ssh_port=$(detect_ssh_port "$host")
            echo "$host|${ssh_port:-22}" >> "$zone_dir/ssh_ports.txt"

            # Try hostname resolution
            local hostname=$(resolve_hostname "$host")
            echo "$host|$hostname" >> "$zone_dir/hostnames.txt"
        else
            log "    No open ports found on scanned ports ($scan_ports)"
        fi
    done < "$zone_dir/hosts.txt"

    log "Zone $zone scan complete"
    return 0
}

# =============================================================================
# Inventory Generation
# =============================================================================

generate_inventory() {
    local output="$1"

    log "Generating inventory file: $output"

    # Get scanner IP for admin_ip
    local scanner_ip=$(get_scanner_ip)

    # Initialize inventory
    local metadata="# Scanned zones: $ZONES
# Scanner IP: $scanner_ip
# Total hosts discovered: $(find "$TEMP_DIR" -name "scan_results.txt" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')"

    init_inventory "$output" "$metadata"

    # Process each zone
    local zone_list=$(echo "$ZONES" | tr ',' ' ')
    for zone in $zone_list; do
        local zone_dir="$TEMP_DIR/$zone"

        if [ ! -f "$zone_dir/scan_results.txt" ]; then
            warn "No results for zone: $zone"
            continue
        fi

        # Add zone description as comment
        local description=$(get_zone_value "$zone" "description")
        echo "" >> "$output"
        echo "[$zone]" >> "$output"
        echo "# $description" >> "$output"

        # Add hosts
        local host_index=1
        while IFS='|' read -r ip ports; do
            [ -z "$ip" ] && continue

            # Get hostname
            local hostname=$(grep "^$ip|" "$zone_dir/hostnames.txt" 2>/dev/null | cut -d'|' -f2)
            if [ -z "$hostname" ] || [ "$hostname" = "$ip" ]; then
                hostname="${zone}$(printf '%02d' $host_index).local"
            fi

            # Get SSH port
            local ssh_port=$(grep "^$ip|" "$zone_dir/ssh_ports.txt" 2>/dev/null | cut -d'|' -f2)
            ssh_port="${ssh_port:-22}"

            # Add host entry
            echo "$hostname ansible_host=$ip ansible_port=$ssh_port ansible_user=$ANSIBLE_USER" >> "$output"

            # Store ports for later analysis
            echo "$zone|$ip|$ports" >> "$TEMP_DIR/all_ports.txt"

            host_index=$((host_index + 1))
        done < "$zone_dir/scan_results.txt"
    done

    # Create group hierarchy
    create_group_hierarchy "$output" "all_servers" "$zone_list"

    # Add global vars
    echo "" >> "$output"
    echo "[all_servers:vars]" >> "$output"
    echo "ansible_python_interpreter=/usr/bin/python3" >> "$output"
    echo "ansible_become_method=sudo" >> "$output"

    # Add zone-specific vars
    for zone in $zone_list; do
        add_zone_variables "$output" "$zone" "$scanner_ip"
    done

    # Add global connection settings
    echo "" >> "$output"
    echo "[all:vars]" >> "$output"
    echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$output"
    echo "ansible_connection=ssh" >> "$output"
    echo "ansible_timeout=30" >> "$output"

    log "Inventory generated successfully"
}

add_zone_variables() {
    local output="$1"
    local zone="$2"
    local scanner_ip="$3"

    echo "" >> "$output"
    echo "[${zone}:vars]" >> "$output"
    echo "# Auto-detected from scanner" >> "$output"
    echo "admin_ip=$scanner_ip" >> "$output"

    # Collect all ports for this zone
    local zone_ports=$(grep "^$zone|" "$TEMP_DIR/all_ports.txt" 2>/dev/null | cut -d'|' -f3 | tr ',' '\n' | sort -u | grep -v '^22$' | tr '\n' ',' | sed 's/,$//')

    if [ -n "$zone_ports" ]; then
        local suggested=$(suggest_allowed_ports "$zone_ports")
        echo "" >> "$output"
        echo "# Detected services - suggested allowed_ports:" >> "$output"

        # Show service comments
        grep "^$zone|" "$TEMP_DIR/all_ports.txt" 2>/dev/null | while IFS='|' read -r z ip ports; do
            local hostname=$(grep "$ip" "$output" | awk '{print $1}' | head -1)
            echo "# $hostname: ports $ports" >> "$output"
        done

        echo "allowed_ports=$suggested" >> "$output"
    fi

    # Add zone-specific vars from config
    local dry_run=$(get_zone_value "$zone" "dry_run")
    local remove_emergency=$(get_zone_value "$zone" "remove_emergency_ssh")
    local run_full=$(get_zone_value "$zone" "run_full_hardening")

    echo "" >> "$output"
    if [ -n "$dry_run" ] && [ "$dry_run" != "0" ]; then
        echo "dry_run=1" >> "$output"
    fi
    if [ "$remove_emergency" = "true" ]; then
        echo "remove_emergency_ssh=true" >> "$output"
    fi
    if [ "$run_full" = "false" ]; then
        echo "run_full_hardening=false" >> "$output"
    fi

    # Add SSH allowed users
    if [ -n "$SSH_ALLOW_USERS" ]; then
        echo "ssh_allow_users=\"$SSH_ALLOW_USERS\"" >> "$output"
    fi
}

# =============================================================================
# Summary
# =============================================================================

show_summary() {
    local output="$1"

    echo ""
    echo "=== Scan Summary ==="
    echo "Zones scanned: $ZONES"
    echo "Output file: $output"
    echo ""

    # Count hosts per zone
    local zone_list=$(echo "$ZONES" | tr ',' ' ')
    for zone in $zone_list; do
        local count=$(grep -c "^\[$zone\]" "$output" 2>/dev/null || echo "0")
        # Ensure count is numeric, default to 0 if empty or non-numeric
        case "$count" in
            ''|*[!0-9]*) count=0 ;;
        esac
        if [ "$count" -gt 0 ]; then
            local host_count=$(awk "/^\[$zone\]/,/^$/ {if (\$0 !~ /^#/ && \$0 !~ /^\[/ && \$0 != \"\") print}" "$output" | wc -l)
            echo "  $zone: $host_count hosts"
        fi
    done

    echo ""
    echo "Next steps:"
    echo "1. Review: vim $output"
    echo "2. Test connectivity: ansible -i $output all -m ping"
    echo "3. Deploy hardening: ansible-playbook -i $output site.yml"
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

# =============================================================================
# Main
# =============================================================================

main() {
    echo "===================================="
    echo "POSIX Hardening Inventory Generator"
    echo "===================================="

    # Check dependencies
    if ! check_nmap; then
        error "nmap is required but not installed"
    fi

    # Check config file
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Config file not found: $CONFIG_FILE"
    fi

    # Parse arguments
    parse_args "$@"

    # Interactive mode
    if [ "$INTERACTIVE" -eq 1 ]; then
        if [ -z "$ZONES" ]; then
            prompt_zones
        fi
        prompt_config
    else
        # Non-interactive: Load defaults from config
        if [ -z "$ANSIBLE_USER" ]; then
            ANSIBLE_USER="$(get_default_value "ansible_user")"
            ANSIBLE_USER="${ANSIBLE_USER:-admin}"
        fi
        if [ -z "$SSH_ALLOW_USERS" ]; then
            SSH_ALLOW_USERS="$(get_default_value "ssh_allow_users")"
            SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-$ANSIBLE_USER}"
        fi
    fi

    # Validate zones
    if [ -z "$ZONES" ]; then
        error "No zones specified"
    fi

    # Set output file
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$(get_yaml_value "$CONFIG_FILE" "default_file")"
        OUTPUT_FILE="${OUTPUT_FILE:-../inventory-generated.ini}"
    fi

    # Make output path absolute
    case "$OUTPUT_FILE" in
        /*) ;;
        *) OUTPUT_FILE="$SCRIPT_DIR/$OUTPUT_FILE" ;;
    esac

    # Backup existing file
    if [ -f "$OUTPUT_FILE" ]; then
        local backup="${OUTPUT_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$OUTPUT_FILE" "$backup"
        log "Backed up existing inventory to: $backup"
    fi

    # Create temp directory
    mkdir -p "$TEMP_DIR"

    # Scan zones
    local zone_list=$(echo "$ZONES" | tr ',' ' ')
    for zone in $zone_list; do
        if [ "$DRY_RUN" -eq 0 ]; then
            scan_zone "$zone"
        else
            log "DRY-RUN: Would scan zone $zone"
        fi
    done

    # Generate inventory
    if [ "$DRY_RUN" -eq 0 ]; then
        generate_inventory "$OUTPUT_FILE"
        show_summary "$OUTPUT_FILE"
    else
        log "DRY-RUN: Would generate inventory at $OUTPUT_FILE"
    fi

    echo ""
    log "Done!"
}

# Run main
main "$@"
