# Automatic Inventory Generator

Intelligent network scanning utility that automatically discovers hosts and generates Ansible inventory files with suggested security configurations.

## Features

- **Multi-Zone Support**: Scan different network zones (production, staging, test) with zone-specific configurations
- **Host Discovery**: Automatic nmap-based host discovery in configured subnets
- **Service Detection**: Identifies running services and suggests appropriate firewall rules
- **SSH Port Detection**: Handles non-standard SSH ports automatically
- **Hostname Resolution**: Attempts DNS resolution with smart fallbacks
- **Security Intelligence**: Provides warnings for dangerous service exposures
- **Auto-Configuration**: Populates admin_ip, allowed_ports, and other variables automatically
- **Interactive & Scriptable**: Supports both interactive prompts and non-interactive automation

## Requirements

### System Requirements
- POSIX-compliant shell (sh, dash, bash)
- nmap (network scanning)
- Standard utilities: awk, sed, grep, nc (optional but recommended)

### Installation
```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install nmap netcat-openbsd

# RHEL/CentOS
sudo yum install nmap nc

# macOS
brew install nmap netcat
```

## Quick Start

### 1. Configure Your Zones

Edit `inventory-config.yml` to define your network zones:

```yaml
zones:
  production:
    subnet: "192.168.1.0/24"
    description: "Production servers - full hardening"
    scan_ports: "22,80,443,3306,5432"
    vars:
      remove_emergency_ssh: false
      run_full_hardening: true
      dry_run: 0
```

### 2. Run Interactive Mode

```bash
cd ansible/utils
./generate-inventory.sh --interactive
```

Follow the prompts to:
1. Select zones to scan
2. Configure Ansible user
3. Specify SSH allowed users
4. Confirm and start scanning

### 3. Review Generated Inventory

```bash
vim ../inventory-generated.ini
```

### 4. Test Connectivity

```bash
cd ..
ansible -i inventory-generated.ini all -m ping
```

### 5. Deploy Hardening

```bash
ansible-playbook -i inventory-generated.ini site.yml
```

## Usage Examples

### Interactive Mode (Default)

```bash
./generate-inventory.sh --interactive
```

Provides step-by-step prompts for all configuration.

### Scan Specific Zone

```bash
./generate-inventory.sh --zone production
```

Scans only the production zone using configuration from `inventory-config.yml`.

### Scan Multiple Zones

```bash
./generate-inventory.sh --zone production,staging
```

Scans multiple zones and combines them into a single inventory.

### Custom Subnet Override

```bash
./generate-inventory.sh --zone test --subnet "10.0.0.0/24"
```

Overrides the subnet defined in the configuration file.

### Custom Output File

```bash
./generate-inventory.sh --zone production --output custom-inventory.ini
```

Saves inventory to a different file.

### Non-Interactive for Automation

```bash
./generate-inventory.sh --zone production --no-confirm
```

Skips confirmation prompts, useful for CI/CD pipelines.

### Dry Run (Preview)

```bash
./generate-inventory.sh --zone production --dry-run
```

Shows what would be scanned without actually performing the scan.

## Configuration Guide

### Zone Configuration

Each zone in `inventory-config.yml` supports:

```yaml
zones:
  zone_name:
    # Required fields
    subnet: "192.168.1.0/24"          # CIDR notation subnet to scan
    description: "Zone description"    # Human-readable description
    scan_ports: "22,80,443"           # Comma-separated ports to scan

    # Optional zone-specific variables
    vars:
      remove_emergency_ssh: false     # Auto-remove emergency SSH after deployment
      run_full_hardening: true        # Run all hardening scripts vs priority 1 only
      dry_run: 0                      # 1 for simulation mode, 0 for real changes
```

### Scan Settings

Configure scanning behavior:

```yaml
scan_settings:
  type: "basic"           # basic|full|fast
  host_timeout: 300       # Timeout per host in seconds
  parallel: 10            # Number of hosts to scan simultaneously
  max_retries: 1          # Retry failed hosts
  skip_host_discovery: false
```

**Scan Types:**
- **basic**: TCP connect scan, no root required, safe, slower
- **full**: SYN scan with version/OS detection, requires root, comprehensive
- **fast**: Quick scan with aggressive timing, faster but less accurate

### Service Detection

Configure port-to-service mapping and security warnings:

```yaml
service_detection:
  enabled: true
  services:
    3306:
      name: "MySQL"
      category: "database"
      suggest_allow: false
      warn: "Consider using trusted_networks instead of public access"
```

### Default Variables

Set defaults for all hosts:

```yaml
defaults:
  ansible_user: "admin"
  ansible_port: 22
  ansible_python_interpreter: "/usr/bin/python3"
  ansible_become_method: "sudo"
  admin_ip: "auto"              # auto|prompt|<IP>
  ssh_allow_users: ""           # Leave empty to prompt
```

## Generated Inventory Structure

The generated inventory file contains:

### 1. Host Entries

```ini
[production]
# Production servers - full hardening
prod01.local ansible_host=192.168.1.10 ansible_port=22 ansible_user=admin
prod02.local ansible_host=192.168.1.11 ansible_port=2222 ansible_user=admin
```

### 2. Group Hierarchy

```ini
[all_servers:children]
production
staging
test
```

### 3. Zone-Specific Variables

```ini
[production:vars]
# Auto-detected from scanner
admin_ip=192.168.1.100

# Detected services - suggested allowed_ports:
# prod01.local: ports 22,80,443
# prod02.local: ports 22,443
allowed_ports=[80, 443]

dry_run=0
run_full_hardening=true
ssh_allow_users="admin deploy"
```

### 4. Global Variables

```ini
[all_servers:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become_method=sudo

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_connection=ssh
ansible_timeout=30
```

## How It Works

### 1. Host Discovery

```bash
nmap -sn -n -T4 "192.168.1.0/24"
```

Performs ping scan to identify live hosts in the subnet.

### 2. Port Scanning

```bash
nmap -sT -Pn -p "22,80,443" <host>
```

Scans specified ports on each discovered host.

### 3. SSH Detection

Checks common SSH ports (22, 2222, 2200, 22000) and identifies the actual SSH port using version detection.

### 4. Service Identification

Maps discovered ports to known services:
- Port 22 → SSH
- Port 80 → HTTP
- Port 443 → HTTPS
- Port 3306 → MySQL
- Port 5432 → PostgreSQL
- Port 6379 → Redis
- Port 27017 → MongoDB

### 5. Intelligent Suggestions

**Auto-Allow Ports:**
- Web services (80, 443, 8080, 8443) are suggested for `allowed_ports`

**Security Warnings:**
- Database ports (3306, 5432, 27017) get warnings to use `trusted_networks`
- Cache services (6379) warned against public exposure
- Search engines (9200) recommended for private networks only

### 6. Variable Population

- **admin_ip**: Auto-detected from scanner's IP address
- **allowed_ports**: Generated from discovered web services
- **ansible_port**: Set to detected SSH port (handles non-standard)
- **Zone variables**: Pulled from configuration file

## Security Considerations

### Network Access

The scanner needs network access to target subnets:
- Ensure firewall rules allow nmap traffic from scanner
- Some scan types require root privileges
- Consider scanning from a trusted management network

### Scan Impact

- **Basic scans**: Low impact, safe for production
- **Full scans**: May trigger IDS/IPS alerts
- **Fast scans**: Higher network load, may impact performance

**Recommendation**: Test in staging environment first.

### Credential Safety

The generator does **NOT**:
- Store passwords
- Perform authentication
- Access systems (only scans externally visible ports)

It only discovers network topology and suggests configurations.

### Generated File Security

The inventory file contains sensitive information:
```bash
# Secure the generated inventory
chmod 600 inventory-generated.ini
```

Consider using Ansible Vault for sensitive variables:
```bash
ansible-vault encrypt_string 'admin,deploy' --name 'ssh_allow_users'
```

## Troubleshooting

### No Hosts Discovered

**Problem**: "Found 0 hosts in zone"

**Root Cause**: The scanner uses ping/ARP for host discovery by default. If hosts don't respond to ping (ICMP blocked by firewall), they won't be discovered.

**Automatic Fallback**: The scanner now automatically tries TCP SYN discovery on ports 22,80,443 if ping scan finds nothing.

**Manual Solutions**:
1. **Check subnet configuration** is correct
2. **Verify network connectivity**: `ping <subnet_gateway>`
3. **Check firewall rules** - ensure either ICMP or TCP ports are accessible
4. **Test manually**:
   ```bash
   # Test ping discovery
   nmap -sn -n -T4 192.168.1.0/24

   # Test TCP discovery (if ping fails)
   nmap -PS22,80,443 -sn -n -T4 192.168.1.0/24
   ```
5. **Try with different subnet** to test: `--subnet "10.0.0.0/24"`

**Note**: The scanner automatically falls back to TCP SYN discovery if ping fails, so in most cases it should find hosts even with ICMP blocked.

### nmap Not Found

**Problem**: "nmap is required but not installed"

**Solution**:
```bash
sudo apt-get install nmap  # Debian/Ubuntu
sudo yum install nmap      # RHEL/CentOS
brew install nmap          # macOS
```

### Permission Denied

**Problem**: Some scan types require root

**Solution**:
```bash
# Use basic scan type (no root required)
# Edit inventory-config.yml:
scan_settings:
  type: "basic"

# OR run with sudo for full scans
sudo ./generate-inventory.sh --zone production
```

### SSH Port Detection Fails

**Problem**: Hosts added but SSH port wrong

**Solution**:
1. Manually verify SSH port: `nmap -p 22,2222 <host>`
2. Add custom SSH ports to config:
   ```yaml
   zones:
     production:
       scan_ports: "22,2222,2200,22000,80,443"
   ```
3. Manually edit generated inventory afterwards

### Duplicate Hosts

**Problem**: Same host appears multiple times

**Solution**:
- Check that zone subnets don't overlap
- Review `inventory-config.yml` for duplicate subnet definitions
- The generator includes `fail_on_duplicates` validation by default

### Slow Scanning

**Problem**: Scans take too long

**Solutions**:
1. Use fast scan type:
   ```yaml
   scan_settings:
     type: "fast"
   ```

2. Reduce scan ports:
   ```yaml
   scan_ports: "22,80,443"  # Instead of many ports
   ```

3. Increase parallel jobs:
   ```yaml
   scan_settings:
     parallel: 20
   ```

4. Reduce host timeout:
   ```yaml
   scan_settings:
     host_timeout: 60
   ```

## Integration with Hardening Playbooks

### Using Generated Inventory

Replace manual inventory with generated one:

```bash
# Generate inventory
cd ansible/utils
./generate-inventory.sh --zone production

# Use with playbook
cd ..
ansible-playbook -i inventory-generated.ini site.yml
```

### Combining with Manual Inventory

You can combine auto-generated with manual entries:

```bash
# Generate base inventory
./generate-inventory.sh --zone production --output production-auto.ini

# Create combined inventory
cat production-auto.ini manual-hosts.ini > inventory.ini
```

### CI/CD Integration

```bash
#!/bin/bash
# deploy.sh

# Generate fresh inventory
cd ansible/utils
./generate-inventory.sh --zone production --no-confirm

# Verify connectivity
cd ..
ansible -i inventory-generated.ini all -m ping

# Deploy hardening
ansible-playbook -i inventory-generated.ini site.yml --diff
```

### Scheduled Discovery

```bash
# Crontab entry for nightly discovery
0 2 * * * cd /path/to/POSIX-hardening/ansible/utils && ./generate-inventory.sh --zone all --no-confirm
```

## Advanced Usage

### Custom Service Detection

Add your own service mappings by editing `lib/service-detector.sh`:

```sh
get_service_name() {
    local port="$1"
    case "$port" in
        22) echo "SSH" ;;
        80) echo "HTTP" ;;
        9000) echo "Custom-App" ;;  # Add custom
        *) echo "Unknown" ;;
    esac
}
```

### Zone Templates

Create zone templates for common setups:

```yaml
# templates/web-servers.yml
zones:
  web_prod:
    subnet: "TO_BE_FILLED"
    description: "Production web servers"
    scan_ports: "22,80,443"
    vars:
      remove_emergency_ssh: false
      run_full_hardening: true
```

### Export to Other Formats

Convert generated INI to other formats:

```bash
# Convert to YAML
ansible-inventory -i inventory-generated.ini --list --yaml > inventory.yml

# Convert to JSON
ansible-inventory -i inventory-generated.ini --list > inventory.json
```

## Library Components

### nmap-scanner.sh

Low-level nmap operations:
- `discover_hosts()` - Find live hosts
- `scan_ports()` - Port scanning
- `get_open_ports()` - Extract open ports
- `detect_ssh_port()` - SSH detection
- `resolve_hostname()` - DNS resolution

### service-detector.sh

Service intelligence:
- `get_service_name()` - Port to service mapping
- `should_allow_port()` - Suggest for firewall
- `get_port_warning()` - Security warnings
- `suggest_allowed_ports()` - Generate port lists

### inventory-builder.sh

Inventory file generation:
- `init_inventory()` - Create header
- `add_host()` - Add host entries
- `add_zone_vars()` - Zone variables
- `create_group_hierarchy()` - Group structure

## Best Practices

### 1. Test in Staging First

Always test scanning and hardening in staging before production:

```bash
# Scan staging
./generate-inventory.sh --zone staging

# Test hardening
cd ..
ansible-playbook -i inventory-generated.ini site.yml --limit staging
```

### 2. Regular Discovery

Run discovery regularly to catch new hosts:

```bash
# Weekly discovery
./generate-inventory.sh --zone production --no-confirm
```

### 3. Review Before Deployment

Always review the generated inventory:

```bash
./generate-inventory.sh --zone production
vim ../inventory-generated.ini
# Review admin_ip, allowed_ports, ssh_allow_users
```

### 4. Backup Existing Inventory

The script automatically backs up, but keep your own:

```bash
cp inventory.ini inventory.ini.manual-backup-$(date +%Y%m%d)
```

### 5. Version Control

Commit generated inventories to track infrastructure changes:

```bash
git add inventory-generated.ini
git commit -m "Updated inventory - discovered 3 new production hosts"
```

## Limitations

- **No Authentication**: Only discovers externally visible services
- **Firewall Restrictions**: Can't scan through firewalls blocking nmap
- **DNS Dependency**: Hostname resolution requires working DNS
- **Network Position**: Must have network access to target subnets
- **Scan Speed**: Large subnets (e.g., /16) may take considerable time

## Support

For issues with the inventory generator:

1. Check this README thoroughly
2. Review `inventory-config.yml` configuration
3. Test with `--dry-run` first
4. Check generated logs and error messages
5. Verify nmap is installed and working: `nmap --version`

For issues with the POSIX Hardening Toolkit itself, refer to the main repository documentation.

## Examples

### Example 1: First Time Setup

```bash
# 1. Install dependencies
sudo apt-get install nmap netcat-openbsd

# 2. Configure your network
vim inventory-config.yml
# Edit production subnet to your network

# 3. Run discovery
./generate-inventory.sh --interactive

# 4. Review results
vim ../inventory-generated.ini

# 5. Test connectivity
cd ..
ansible -i inventory-generated.ini all -m ping

# 6. Deploy hardening
ansible-playbook -i inventory-generated.ini site.yml
```

### Example 2: Multi-Zone Environment

```bash
# Scan all zones
./generate-inventory.sh --zone production,staging,test --no-confirm

# Review generated groups
cd ..
ansible-inventory -i inventory-generated.ini --graph

# Deploy to staging first
ansible-playbook -i inventory-generated.ini site.yml --limit staging

# After verification, deploy to production
ansible-playbook -i inventory-generated.ini site.yml --limit production
```

### Example 3: Custom Network Setup

```bash
# Create custom zone config
cat >> inventory-config.yml <<EOF
zones:
  dmz:
    subnet: "10.0.10.0/24"
    description: "DMZ web servers"
    scan_ports: "22,80,443,8080,8443"
    vars:
      remove_emergency_ssh: true
      run_full_hardening: true
EOF

# Scan DMZ
./generate-inventory.sh --zone dmz --output ../inventory-dmz.ini

# Use DMZ-specific inventory
cd ..
ansible-playbook -i inventory-dmz.ini site.yml
```

## License

This utility is part of the POSIX Hardening Toolkit and follows the same license.
