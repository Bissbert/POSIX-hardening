#!/bin/sh
# ==============================================================================
# Service Detection Library
# ==============================================================================
# Maps discovered ports to services and provides intelligent suggestions
# for firewall configuration
# ==============================================================================

# Map port number to service name
# Usage: get_service_name <port>
get_service_name() {
    local port="$1"

    case "$port" in
        22) echo "SSH" ;;
        80) echo "HTTP" ;;
        443) echo "HTTPS" ;;
        3306) echo "MySQL" ;;
        5432) echo "PostgreSQL" ;;
        6379) echo "Redis" ;;
        8080) echo "HTTP-Alt" ;;
        9200) echo "Elasticsearch" ;;
        27017) echo "MongoDB" ;;
        3000) echo "Application" ;;
        8443) echo "HTTPS-Alt" ;;
        5000) echo "Application" ;;
        *) echo "Unknown" ;;
    esac
}

# Get service category
# Usage: get_service_category <port>
get_service_category() {
    local port="$1"

    case "$port" in
        22) echo "management" ;;
        80|443|8080|8443) echo "web" ;;
        3306|5432|27017) echo "database" ;;
        6379) echo "cache" ;;
        9200) echo "search" ;;
        *) echo "other" ;;
    esac
}

# Check if port should be suggested for allowed_ports
# Usage: should_allow_port <port>
# Returns: 0 if yes, 1 if no
should_allow_port() {
    local port="$1"

    case "$port" in
        22) return 1 ;;  # SSH always allowed separately
        80|443|8080|8443) return 0 ;;  # Web services
        *) return 1 ;;  # Everything else needs consideration
    esac
}

# Get security warning for a port
# Usage: get_port_warning <port>
get_port_warning() {
    local port="$1"

    case "$port" in
        3306) echo "Consider using trusted_networks instead of public access" ;;
        5432) echo "Consider using trusted_networks instead of public access" ;;
        6379) echo "Redis should not be exposed publicly - use trusted_networks" ;;
        9200) echo "Elasticsearch should be on private network only" ;;
        27017) echo "MongoDB should not be exposed publicly - use trusted_networks" ;;
        *) echo "" ;;
    esac
}

# Generate allowed_ports suggestion from discovered ports
# Usage: suggest_allowed_ports <port_list>
# port_list: comma-separated list of ports
# Returns: YAML array format
suggest_allowed_ports() {
    local ports="$1"
    local result=""

    # Convert comma-separated to space-separated
    local port_array=$(echo "$ports" | tr ',' ' ')

    for port in $port_array; do
        if should_allow_port "$port"; then
            if [ -z "$result" ]; then
                result="$port"
            else
                result="$result, $port"
            fi
        fi
    done

    if [ -n "$result" ]; then
        echo "[$result]"
    else
        echo "[]"
    fi
}

# Generate service detection comment for inventory
# Usage: generate_service_comment <hostname> <ports>
generate_service_comment() {
    local hostname="$1"
    local ports="$2"

    echo "# $hostname: Detected services:"
    for port in $(echo "$ports" | tr ',' ' '); do
        local service=$(get_service_name "$port")
        local warning=$(get_port_warning "$port")

        if [ -n "$warning" ]; then
            echo "#   Port $port ($service) - WARNING: $warning"
        else
            echo "#   Port $port ($service)"
        fi
    done
}

# Detect host type based on open ports
# Usage: detect_host_type <ports>
detect_host_type() {
    local ports="$1"

    # Web server
    if echo "$ports" | grep -qE '80|443|8080'; then
        echo "web-server"
        return
    fi

    # Database server
    if echo "$ports" | grep -qE '3306|5432|27017|6379'; then
        echo "database-server"
        return
    fi

    # Application server
    if echo "$ports" | grep -qE '3000|5000|8000'; then
        echo "app-server"
        return
    fi

    echo "server"
}
