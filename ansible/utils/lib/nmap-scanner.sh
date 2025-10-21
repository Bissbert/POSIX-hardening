#!/bin/sh
# ==============================================================================
# Nmap Scanner Library
# ==============================================================================
# POSIX-compliant wrapper for nmap network scanning
# Provides host discovery, port scanning, and service detection
# ==============================================================================

# Check if nmap is installed
check_nmap() {
    if ! command -v nmap >/dev/null 2>&1; then
        echo "ERROR: nmap is not installed" >&2
        echo "Install with: sudo apt-get install nmap" >&2
        return 1
    fi
    return 0
}

# Get nmap version
get_nmap_version() {
    nmap --version 2>/dev/null | head -1 | awk '{print $3}'
}

# Check if running as root (needed for SYN scans)
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# =============================================================================
# Host Discovery
# =============================================================================

# Discover live hosts in a subnet
# Usage: discover_hosts <subnet> [output_file]
# Example: discover_hosts "192.168.1.0/24" "/tmp/hosts.txt"
discover_hosts() {
    local subnet="$1"
    local output_file="${2:-/tmp/discovered_hosts.txt}"

    if [ -z "$subnet" ]; then
        echo "ERROR: subnet required" >&2
        return 1
    fi

    echo "Discovering hosts in $subnet..." >&2

    # Method 1: Standard ping/ARP scan (works for most networks)
    # -sn = no port scan, just host discovery
    # -n = no DNS resolution (faster)
    # -T4 = aggressive timing
    nmap -sn -n -T4 "$subnet" 2>/dev/null | \
        grep "Nmap scan report for" | \
        awk '{print $NF}' | \
        tr -d '()' > "$output_file"

    local count=$(wc -l < "$output_file")

    # If no hosts found, try TCP SYN discovery (for firewalled networks)
    if [ "$count" -eq 0 ]; then
        echo "No hosts found via ping, trying TCP SYN discovery..." >&2
        # Try common service ports (SSH, HTTP, HTTPS)
        nmap -PS22,80,443 -sn -n -T4 "$subnet" 2>/dev/null | \
            grep "Nmap scan report for" | \
            awk '{print $NF}' | \
            tr -d '()' > "$output_file"
        count=$(wc -l < "$output_file")
    fi

    echo "Discovered $count live hosts" >&2

    if [ "$count" -eq 0 ]; then
        return 1
    fi

    return 0
}

# =============================================================================
# Port Scanning
# =============================================================================

# Scan specific ports on a host
# Usage: scan_ports <host> <ports> [scan_type]
# scan_type: basic (default), full, fast
# Example: scan_ports "192.168.1.10" "22,80,443" "basic"
scan_ports() {
    local host="$1"
    local ports="$2"
    local scan_type="${3:-basic}"

    if [ -z "$host" ] || [ -z "$ports" ]; then
        echo "ERROR: host and ports required" >&2
        return 1
    fi

    local scan_opts=""

    case "$scan_type" in
        basic)
            # TCP connect scan (no root required)
            scan_opts="-sT -Pn"
            ;;
        full)
            # SYN scan with version detection (requires root)
            if is_root; then
                scan_opts="-sS -sV -O -Pn"
            else
                echo "WARN: full scan requires root, falling back to basic" >&2
                scan_opts="-sT -Pn"
            fi
            ;;
        fast)
            # Fast scan with aggressive timing
            scan_opts="-sT -Pn -T4 --min-rate=1000"
            ;;
        *)
            echo "ERROR: Invalid scan type: $scan_type" >&2
            return 1
            ;;
    esac

    # Perform scan and parse output
    # -n = no DNS
    # --open = only show open ports
    # -p = ports to scan
    nmap $scan_opts -n --open -p "$ports" "$host" 2>/dev/null
}

# Get only open ports from a host
# Usage: get_open_ports <host> <ports> [scan_type]
# Returns: comma-separated list of open ports
get_open_ports() {
    local host="$1"
    local ports="$2"
    local scan_type="${3:-basic}"

    scan_ports "$host" "$ports" "$scan_type" 2>/dev/null | \
        grep "^[0-9]" | \
        grep "/tcp.*open" | \
        awk '{print $1}' | \
        cut -d'/' -f1 | \
        tr '\n' ',' | \
        sed 's/,$//'
}

# Check if a specific port is open
# Usage: is_port_open <host> <port>
is_port_open() {
    local host="$1"
    local port="$2"

    if [ -z "$host" ] || [ -z "$port" ]; then
        return 1
    fi

    # Quick check with timeout
    nmap -p "$port" --open -Pn -T4 "$host" 2>/dev/null | \
        grep -q "^${port}/tcp.*open"
}

# =============================================================================
# Service Detection
# =============================================================================

# Detect SSH port (may not be 22)
# Usage: detect_ssh_port <host>
# Returns: SSH port number or empty if not found
detect_ssh_port() {
    local host="$1"

    if [ -z "$host" ]; then
        return 1
    fi

    # Check common SSH ports
    local common_ports="22,2222,2200,22000"

    # Scan for SSH service
    nmap -p "$common_ports" -sV --open -Pn "$host" 2>/dev/null | \
        grep "/tcp.*open.*ssh" | \
        head -1 | \
        awk '{print $1}' | \
        cut -d'/' -f1
}

# Get service version info for open ports
# Usage: get_service_versions <host> <ports>
# Requires root for best results
get_service_versions() {
    local host="$1"
    local ports="$2"

    if [ -z "$host" ] || [ -z "$ports" ]; then
        return 1
    fi

    local scan_opts="-sT -sV -Pn"
    if is_root; then
        scan_opts="-sS -sV -Pn"
    fi

    nmap $scan_opts -p "$ports" "$host" 2>/dev/null | \
        grep "^[0-9]" | \
        grep "/tcp.*open"
}

# =============================================================================
# OS Detection
# =============================================================================

# Detect operating system (requires root)
# Usage: detect_os <host>
detect_os() {
    local host="$1"

    if [ -z "$host" ]; then
        return 1
    fi

    if ! is_root; then
        echo "WARN: OS detection requires root privileges" >&2
        return 1
    fi

    nmap -O -Pn "$host" 2>/dev/null | \
        grep "^OS details:" | \
        cut -d':' -f2- | \
        sed 's/^[[:space:]]*//'
}

# =============================================================================
# Hostname Resolution
# =============================================================================

# Resolve hostname via reverse DNS
# Usage: resolve_hostname <ip>
resolve_hostname() {
    local ip="$1"

    if [ -z "$ip" ]; then
        return 1
    fi

    # Try nmap's built-in DNS resolution first
    local hostname=$(nmap -sL "$ip" 2>/dev/null | \
        grep "Nmap scan report for" | \
        awk '{print $5}' | \
        tr -d '()')

    # Fallback to host command
    if [ -z "$hostname" ] || [ "$hostname" = "$ip" ]; then
        hostname=$(host "$ip" 2>/dev/null | \
            grep "domain name pointer" | \
            awk '{print $NF}' | \
            sed 's/\.$//')
    fi

    # Return hostname or IP if resolution failed
    if [ -n "$hostname" ] && [ "$hostname" != "$ip" ]; then
        echo "$hostname"
    else
        echo "$ip"
    fi
}

# =============================================================================
# Batch Scanning
# =============================================================================

# Scan multiple hosts in parallel
# Usage: scan_hosts_parallel <hosts_file> <ports> <output_dir> [parallel_jobs]
scan_hosts_parallel() {
    local hosts_file="$1"
    local ports="$2"
    local output_dir="$3"
    local parallel_jobs="${4:-10}"

    if [ ! -f "$hosts_file" ]; then
        echo "ERROR: hosts file not found: $hosts_file" >&2
        return 1
    fi

    mkdir -p "$output_dir"

    local count=0
    local pids=""

    while read -r host; do
        [ -z "$host" ] && continue

        # Start scan in background
        (
            local out_file="$output_dir/$(echo "$host" | tr '.' '_').txt"
            scan_ports "$host" "$ports" "basic" > "$out_file" 2>&1
        ) &

        pids="$pids $!"
        count=$((count + 1))

        # Wait if we've reached parallel limit
        if [ $((count % parallel_jobs)) -eq 0 ]; then
            wait
            pids=""
        fi
    done < "$hosts_file"

    # Wait for remaining jobs
    wait

    echo "Scanned $count hosts" >&2
}

# =============================================================================
# Output Parsing
# =============================================================================

# Parse nmap output to JSON-like format
# Usage: parse_scan_result <scan_output_file>
parse_scan_result() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    awk '
    /Nmap scan report for/ {
        if (host != "") print "}"
        host = $NF
        gsub(/[()]/, "", host)
        printf "{\"host\":\"%s\",\"ports\":[", host
        first = 1
    }
    /^[0-9]+\/tcp/ {
        port = $1
        gsub(/\/tcp/, "", port)
        state = $2
        service = $3
        if (first == 0) printf ","
        printf "{\"port\":%s,\"state\":\"%s\",\"service\":\"%s\"}", port, state, service
        first = 0
    }
    END {
        if (host != "") print "]}"
    }
    ' "$file"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if subnet is valid
validate_subnet() {
    local subnet="$1"

    echo "$subnet" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
}

# Get scanner's IP address (useful for admin_ip)
get_scanner_ip() {
    # Try to get IP from default route interface (Linux)
    if command -v ip >/dev/null 2>&1; then
        ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
        return
    fi

    # macOS fallback: use route and ifconfig
    if command -v route >/dev/null 2>&1 && command -v ifconfig >/dev/null 2>&1; then
        local default_if=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}')
        if [ -n "$default_if" ]; then
            ifconfig "$default_if" 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1
            return
        fi
    fi

    # Final fallback: get any non-loopback IP
    if command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null | awk '{print $1}'
    fi
}

# Test SSH connectivity
# Usage: test_ssh_connection <host> [port] [timeout]
test_ssh_connection() {
    local host="$1"
    local port="${2:-22}"
    local timeout="${3:-5}"

    # Try to connect to SSH (will fail at auth, but that's OK)
    timeout "$timeout" sh -c "echo '' | nc -w 1 $host $port" >/dev/null 2>&1
}
