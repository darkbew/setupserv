#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Preflight Check
# ==============================================================================
#
# Description:
#   Validates system requirements before any changes are made.
#   This script is READ-ONLY — it does not modify the system host state.
#
# Checks:
#   - Root privileges & Ubuntu LTS version
#   - Base system utilities & port availability
#   - CPU architecture (x86_64, amd64, aarch64, arm64) & CPU cores
#   - RAM & SWAP configuration
#   - Disk space, filesystem type, SSD detection, inode usage, mount options
#   - Virtualization environment & pending reboot status
#   - Security modules (AppArmor/SELinux) & Time synchronization (NTP)
#   - Internet connectivity & DNS resolution (POSIX/native resolver)
#   - Environment file & critical variables
#
# Usage:
#   sudo bash bootstrap/00-preflight.sh
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ==============================================================================
# CHECK FUNCTIONS
# ==============================================================================

# Verify presence of essential system binaries
check_required_tools() {
    local tools=("curl" "awk" "grep" "findmnt" "lsblk" "df" "sysctl" "ip" "systemctl" "getent")
    local missing=()
    local tool

    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required base system tool(s): ${missing[*]}"
        log_error "Please install base system packages before running bootstrap."
        exit 1
    fi

    log_success "Base system utilities: OK"
}

# Verify CPU Architecture (x86_64, amd64, aarch64, arm64 supported)
check_architecture() {
    local arch
    arch=$(uname -m)

    case "${arch}" in
        x86_64|amd64|aarch64|arm64)
            log_success "Architecture: ${arch}"
            ;;
        *)
            log_error "Unsupported architecture: ${arch}. Supported: x86_64, amd64, aarch64, arm64."
            exit 1
            ;;
    esac
}

# Verify CPU Cores
check_cpu_cores() {
    local min_cores="${PREFLIGHT_MIN_CPU_CORES:-${DEFAULT_MIN_CPU_CORES:-2}}"
    local cores=0

    if command -v nproc &>/dev/null; then
        cores=$(nproc)
    elif [[ -f /proc/cpuinfo ]]; then
        cores=$(grep -c '^processor' /proc/cpuinfo || echo 1)
    fi

    if [[ "${cores}" -lt 1 ]]; then
        log_error "Could not detect CPU cores."
        exit 1
    elif [[ "${cores}" -lt "${min_cores}" ]]; then
        log_warn "CPU Cores: ${cores} (minimum ${min_cores} vCPUs recommended for production workloads)"
    else
        log_success "CPU Cores: ${cores}"
    fi
}

# Verify RAM Capacity
check_ram() {
    local min_ram_mb="${PREFLIGHT_MIN_RAM_MB:-${DEFAULT_MIN_RAM_MB:-2048}}"
    local rec_ram_mb="${PREFLIGHT_REC_RAM_MB:-${DEFAULT_REC_RAM_MB:-8192}}"
    local total_kb=0
    local total_mb=0
    local total_gb=0

    if [[ -f /proc/meminfo ]]; then
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        total_mb=$((total_kb / 1024))
        total_gb=$((total_mb / 1024))
    else
        log_error "Cannot read /proc/meminfo"
        exit 1
    fi

    if [[ "${total_mb}" -lt "${min_ram_mb}" ]]; then
        log_error "Insufficient RAM: ${total_gb}GB (minimum ${min_ram_mb}MB required)"
        exit 1
    elif [[ "${total_mb}" -lt "${rec_ram_mb}" ]]; then
        log_warn "RAM: ${total_gb}GB (recommended $((rec_ram_mb / 1024))GB+ for production workloads)"
    else
        log_success "RAM: ${total_gb}GB"
    fi
}

# Verify SWAP Configuration
check_swap() {
    local min_swap_mb="${PREFLIGHT_MIN_SWAP_MB:-${DEFAULT_MIN_SWAP_MB:-2048}}"
    local swap_kb=0
    local swap_gb=0

    if [[ -f /proc/meminfo ]]; then
        swap_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
        swap_gb=$((swap_kb / 1024 / 1024))
    fi

    if [[ "${swap_kb}" -eq 0 ]]; then
        log_warn "SWAP: None configured (SWAP $((min_swap_mb / 1024))GB+ recommended to prevent OOM during heavy application builds)"
    else
        log_success "SWAP: ${swap_gb}GB"
    fi
}

# Verify Disk Space
check_disk_space() {
    local min_disk_gb="${PREFLIGHT_MIN_DISK_GB:-${DEFAULT_MIN_DISK_GB:-20}}"
    local warn_disk_gb="${PREFLIGHT_WARN_DISK_GB:-${DEFAULT_WARN_DISK_GB:-50}}"
    local free_kb=0
    local free_gb=0

    # Robust parsing: df --output=avail eliminates multi-line header/awk issues
    free_kb=$(df --output=avail / | tail -n1 | tr -d ' ')
    free_gb=$((free_kb / 1024 / 1024))

    if [[ "${free_gb}" -lt "${min_disk_gb}" ]]; then
        log_error "Insufficient disk space: ${free_gb}GB free (minimum ${min_disk_gb}GB required)"
        exit 1
    elif [[ "${free_gb}" -lt "${warn_disk_gb}" ]]; then
        log_warn "Disk space: ${free_gb}GB free (recommended ${warn_disk_gb}GB+)"
    else
        log_success "Disk space: ${free_gb}GB free"
    fi
}

# Verify Filesystem, Storage Type (SSD/NVMe), and Mount Options
check_filesystem_and_storage() {
    local root_info=""
    local fs_type=""
    local mount_opts=""
    local root_source=""

    root_info=$(findmnt -n -o FSTYPE,OPTIONS,SOURCE / 2>/dev/null || true)
    read -r fs_type mount_opts root_source <<< "${root_info}"

    # Filesystem check
    case "${fs_type}" in
        ext4|xfs) log_success "Filesystem: ${fs_type}" ;;
        btrfs)    log_warn "Filesystem: ${fs_type} — ext4/xfs recommended for database stability" ;;
        *)        log_warn "Filesystem: ${fs_type:-unknown} — ext4 or xfs recommended" ;;
    esac

    # Disk type check (SSD vs HDD vs NVMe)
    local disk_name=""
    if [[ -n "${root_source}" ]]; then
        disk_name=$(lsblk -nd -o PKNAME "${root_source}" 2>/dev/null || true)
    fi

    if [[ -n "${disk_name}" ]] && [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
        local rotational
        rotational=$(cat "/sys/block/${disk_name}/queue/rotational" 2>/dev/null || echo "1")
        if [[ "${rotational}" == "0" ]]; then
            if [[ "${disk_name}" == nvme* ]]; then
                log_success "Disk type: NVMe SSD (${disk_name})"
            else
                log_success "Disk type: SSD (${disk_name})"
            fi
        else
            log_warn "Disk type: HDD (${disk_name}) — SSD/NVMe strongly recommended for database performance"
        fi
    else
        log_info "Disk type: could not detect block device queue"
    fi

    # Mount options check
    if [[ -n "${mount_opts}" ]]; then
        log_info "Root mount options: ${mount_opts}"
        if [[ "${mount_opts}" != *"noatime"* ]]; then
            log_info "Tip: Consider adding 'noatime' to /etc/fstab for SSD optimization"
        fi
    fi
}

# Verify Inode Usage
check_inode_usage() {
    local inode_pct=""
    inode_pct=$(df -i / | tail -n1 | awk '{print $5}' | tr -d '%')

    if [[ ! "${inode_pct}" =~ ^[0-9]+$ ]]; then
        log_warn "Unable to determine inode usage"
        return
    fi

    if [[ "${inode_pct}" -gt 80 ]]; then
        log_warn "Inode usage: ${inode_pct}% (high — may cause issue during package extraction)"
    else
        log_success "Inode usage: ${inode_pct}%"
    fi
}

# Inspect Linux Security Modules (AppArmor / SELinux)
check_security_modules() {
    local apparmor_status="disabled/absent"
    local selinux_status="disabled/absent"

    if command -v aa-status &>/dev/null; then
        if aa-status --enabled 2>/dev/null; then
            apparmor_status="enabled"
        fi
    elif [[ -d /sys/kernel/security/apparmor ]]; then
        apparmor_status="present"
    fi

    if command -v getenforce &>/dev/null; then
        selinux_status=$(getenforce 2>/dev/null || echo "disabled")
    fi

    log_info "Security Modules — AppArmor: ${apparmor_status}, SELinux: ${selinux_status}"
}

# Detect Virtualization Environment
check_virtualization() {
    local virt_type="baremetal"

    if command -v systemd-detect-virt &>/dev/null; then
        virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
    fi

    case "${virt_type}" in
        none|kvm|qemu|vmware|xen|hyperv)
            log_success "Virtualization: ${virt_type}"
            ;;
        lxc|openvz|docker|podman)
            log_warn "Virtualization: ${virt_type} (container-in-container execution may restrict Docker/Tailscale)"
            ;;
        *)
            log_info "Virtualization: ${virt_type}"
            ;;
    esac
}

# Check for Pending Kernel Reboot
check_pending_reboot() {
    if [[ -f /var/run/reboot-required ]]; then
        log_warn "Pending System Reboot detected (/var/run/reboot-required exists)."
        log_warn "Consider rebooting the server before proceeding if a kernel upgrade occurred."
    else
        log_success "Pending Reboot: None"
    fi
}

# Verify System Time Synchronization (NTP & RTC)
check_time_sync() {
    local ntp_sync="unknown"
    local tz="unknown"

    if command -v timedatectl &>/dev/null; then
        ntp_sync=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "no")
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")

        if [[ "${ntp_sync}" == "yes" ]]; then
            log_success "Time synchronization (NTP): Active (${tz})"
        else
            log_warn "Time synchronization (NTP): Not synchronized (current timezone: ${tz})"
        fi
    else
        log_warn "timedatectl not available — skipping time synchronization check"
    fi
}

# Check for Port Conflicts
check_port_conflicts() {
    local conflict=0
    local port
    local ports=()

    if [[ -n "${PREFLIGHT_PORTS:-}" ]]; then
        read -r -a ports <<< "${PREFLIGHT_PORTS}"
    else
        ports=(80 443)
    fi

    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warn "Host port ${port} is currently in use by an existing process."
            conflict=$((conflict + 1))
        fi
    done

    if [[ "${conflict}" -gt 0 ]]; then
        log_warn "Port conflicts detected — ensure no conflicting webservers interfere with reverse proxy services later."
    else
        log_success "Port availability (${ports[*]}): Clean"
    fi
}

# Verify Outbound Internet Connectivity
check_internet() {
    log_info "Checking internet connectivity..."

    if ! retry 3 2 curl -sfL --connect-timeout 5 --max-time 10 \
        -o /dev/null "https://archive.ubuntu.com"; then
        log_error "No internet connectivity. Check network configuration."
        exit 1
    fi

    log_success "Internet: connected"
}

# Verify Native DNS Resolution
check_dns() {
    log_info "Checking DNS resolution..."

    # Native POSIX / Ubuntu 24.04 resolver check (does not depend on dnsutils/bind9-host)
    if getent ahosts archive.ubuntu.com > /dev/null 2>&1 || getent hosts archive.ubuntu.com > /dev/null 2>&1; then
        log_success "DNS: resolving"
        return 0
    fi

    log_error "DNS resolution failed. Check /etc/resolv.conf or network settings."
    exit 1
}

# Verify Environment File and Critical Variables
check_env_file() {
    local env_file="${PROJECT_ROOT}/.env"

    if [[ ! -f "${env_file}" ]]; then
        log_warn "Environment file not found at ${env_file} (skipping environment variable checks)"
        return 0
    fi

    log_success "Environment file: ${env_file}"

    # Load environment variables
    load_env "${env_file}"

    log_success "Environment file loaded and validated"
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

main() {
    check_root
    print_header "Preflight Check" "Validating system requirements"

    log_section "System & Environment"
    check_required_tools
    check_os
    check_architecture
    check_security_modules
    check_virtualization
    check_pending_reboot
    check_time_sync

    log_section "Hardware & Resources"
    check_cpu_cores
    check_ram
    check_swap
    check_disk_space

    log_section "Storage & Filesystem"
    check_filesystem_and_storage
    check_inode_usage

    log_section "Network & Ports"
    check_internet
    check_dns
    check_port_conflicts

    log_section "Environment Configuration"
    check_env_file

    printf '\n'
    log_success "All preflight checks passed"
    printf '\n'
}

main "$@"
