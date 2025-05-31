#!/bin/bash

# ODIN Dashboard Restore Script
# This script restores Grafana dashboards from backup files

set -euo pipefail

NAMESPACE="monitoring"
BACKUP_DIR="/home/magicat777/projects/ODIN/backups/dashboards"
RESTORE_SOURCE=""
DRY_RUN=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show available backups
list_backups() {
    log_info "Available backups in ${BACKUP_DIR}:"
    
    if [ ! -d "${BACKUP_DIR}" ]; then
        log_warning "Backup directory does not exist: ${BACKUP_DIR}"
        return 1
    fi
    
    local count=0
    for archive in "${BACKUP_DIR}"/odin-dashboards-*.tar.gz; do
        if [ -f "${archive}" ]; then
            local basename=$(basename "${archive}")
            local timestamp=$(echo "${basename}" | sed 's/odin-dashboards-\(.*\)\.tar\.gz/\1/')
            local size=$(du -h "${archive}" | cut -f1)
            local date=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" 2>/dev/null || echo "Unknown")
            
            echo "  ${basename} (${size}, ${date})"
            ((count++))
        fi
    done
    
    if [ "${count}" -eq 0 ]; then
        log_warning "No backup archives found"
        return 1
    fi
    
    log_info "Total backups found: ${count}"
}

# Extract backup archive
extract_backup() {
    local archive_path="$1"
    local extract_dir="/tmp/odin-dashboard-restore-$$"
    
    log_info "Extracting backup archive: $(basename "${archive_path}")"
    
    mkdir -p "${extract_dir}"
    
    if tar -xzf "${archive_path}" -C "${extract_dir}"; then
        local extracted_dir=$(find "${extract_dir}" -maxdepth 1 -type d -name "2*" | head -1)
        if [ -n "${extracted_dir}" ]; then
            echo "${extracted_dir}"
            return 0
        else
            log_error "Could not find extracted directory"
            rm -rf "${extract_dir}"
            return 1
        fi
    else
        log_error "Failed to extract backup archive"
        rm -rf "${extract_dir}"
        return 1
    fi
}

# Validate backup directory
validate_backup() {
    local backup_path="$1"
    
    log_info "Validating backup directory: ${backup_path}"
    
    if [ ! -d "${backup_path}" ]; then
        log_error "Backup directory does not exist: ${backup_path}"
        return 1
    fi
    
    local manifest_file="${backup_path}/backup-manifest.json"
    if [ ! -f "${manifest_file}" ]; then
        log_error "Backup manifest not found: ${manifest_file}"
        return 1
    fi
    
    local dashboard_count=$(find "${backup_path}" -name "*.yaml" -not -name "backup-manifest.json" | wc -l)
    local manifest_count=$(jq -r '.backup_info.dashboard_count // 0' "${manifest_file}" 2>/dev/null || echo "0")
    
    log_info "Dashboard files found: ${dashboard_count}"
    log_info "Manifest dashboard count: ${manifest_count}"
    
    if [ "${dashboard_count}" -ne "${manifest_count}" ]; then
        log_warning "Dashboard count mismatch (files: ${dashboard_count}, manifest: ${manifest_count})"
        if [ "${FORCE}" != "true" ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    fi
    
    log_success "Backup validation completed"
    return 0
}

# Check for existing dashboards
check_existing_dashboards() {
    local backup_path="$1"
    
    log_info "Checking for existing dashboards in namespace ${NAMESPACE}"
    
    local existing_cms
    existing_cms=$(kubectl get configmaps -n "${NAMESPACE}" -l grafana_dashboard=1 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "${existing_cms}" ]; then
        log_warning "Found existing dashboard ConfigMaps: ${existing_cms}"
        
        if [ "${FORCE}" != "true" ]; then
            echo -n "This will overwrite existing dashboards. Continue? [y/N]: "
            read -r response
            if [[ ! "${response}" =~ ^[Yy]$ ]]; then
                log_info "Restore cancelled by user"
                return 1
            fi
        else
            log_info "Force mode enabled, will overwrite existing dashboards"
        fi
    fi
    
    return 0
}

# Restore single dashboard
restore_dashboard() {
    local dashboard_file="$1"
    local dashboard_name=$(basename "${dashboard_file}" .yaml)
    
    if [ "${DRY_RUN}" == "true" ]; then
        log_info "[DRY RUN] Would restore: ${dashboard_name}"
        return 0
    fi
    
    log_info "Restoring dashboard: ${dashboard_name}"
    
    if kubectl apply -f "${dashboard_file}" 2>/dev/null; then
        log_success "Restored: ${dashboard_name}"
        return 0
    else
        log_error "Failed to restore: ${dashboard_name}"
        return 1
    fi
}

# Verify kubectl access
verify_kubectl_access() {
    log_info "Verifying kubectl access to namespace ${NAMESPACE}"
    
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        log_error "Cannot access namespace ${NAMESPACE}"
        return 1
    fi
    
    if [ "${DRY_RUN}" != "true" ]; then
        if ! kubectl auth can-i create configmaps -n "${NAMESPACE}" >/dev/null 2>&1; then
            log_error "Insufficient permissions to create ConfigMaps in ${NAMESPACE}"
            return 1
        fi
    fi
    
    log_success "kubectl access verified"
}

# Main restore function
main() {
    log_info "Starting ODIN Dashboard Restore"
    
    if [ -z "${RESTORE_SOURCE}" ]; then
        log_error "No restore source specified"
        list_backups
        exit 1
    fi
    
    verify_kubectl_access
    
    local backup_path=""
    
    # Determine if source is archive or directory
    if [ -f "${RESTORE_SOURCE}" ]; then
        log_info "Restore source is archive file: ${RESTORE_SOURCE}"
        backup_path=$(extract_backup "${RESTORE_SOURCE}")
        if [ $? -ne 0 ]; then
            exit 1
        fi
    elif [ -d "${RESTORE_SOURCE}" ]; then
        log_info "Restore source is directory: ${RESTORE_SOURCE}"
        backup_path="${RESTORE_SOURCE}"
    else
        # Try to find archive by timestamp
        local archive_file="${BACKUP_DIR}/odin-dashboards-${RESTORE_SOURCE}.tar.gz"
        if [ -f "${archive_file}" ]; then
            log_info "Found archive by timestamp: ${archive_file}"
            backup_path=$(extract_backup "${archive_file}")
            if [ $? -ne 0 ]; then
                exit 1
            fi
        else
            log_error "Restore source not found: ${RESTORE_SOURCE}"
            list_backups
            exit 1
        fi
    fi
    
    validate_backup "${backup_path}"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    check_existing_dashboards "${backup_path}"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Restore dashboards
    local success_count=0
    local total_count=0
    
    for dashboard_file in "${backup_path}"/*.yaml; do
        if [ -f "${dashboard_file}" ] && [[ "$(basename "${dashboard_file}")" != "backup-manifest.json" ]]; then
            ((total_count++))
            if restore_dashboard "${dashboard_file}"; then
                ((success_count++))
            fi
        fi
    done
    
    log_info "Restore progress: ${success_count}/${total_count} dashboards"
    
    if [ "${success_count}" -eq 0 ]; then
        log_error "No dashboards were successfully restored"
        exit 1
    fi
    
    # Cleanup extracted files if we extracted an archive
    if [[ "${backup_path}" == "/tmp/odin-dashboard-restore-"* ]]; then
        rm -rf "$(dirname "${backup_path}")"
    fi
    
    if [ "${DRY_RUN}" == "true" ]; then
        log_success "Dry run completed - ${success_count} dashboards would be restored"
    else
        log_success "Dashboard restore completed successfully"
        log_info "Restored ${success_count} dashboards to namespace ${NAMESPACE}"
        
        # Restart Grafana to reload dashboards
        log_info "Restarting Grafana to reload dashboards"
        kubectl rollout restart deployment/grafana -n "${NAMESPACE}" >/dev/null 2>&1 || true
    fi
}

# Show help
show_help() {
    cat << EOF
ODIN Dashboard Restore Script

Usage: $0 [OPTIONS] SOURCE

Restore Grafana dashboard ConfigMaps from backup files.

SOURCE can be:
  - Archive file path (e.g., /path/to/odin-dashboards-20231201_143000.tar.gz)
  - Directory path (e.g., /path/to/backup/20231201_143000/)
  - Timestamp (e.g., 20231201_143000) - will look for archive in backup directory

Options:
  -h, --help              Show this help message
  -n, --namespace NS      Target namespace (default: monitoring)
  -d, --dry-run          Show what would be restored without making changes
  -f, --force            Force restore without prompts
  -l, --list             List available backups and exit

Examples:
  $0 -l                                    # List available backups
  $0 20231201_143000                      # Restore from timestamp
  $0 /path/to/backup.tar.gz               # Restore from archive
  $0 -d 20231201_143000                   # Dry run restore
  $0 -f -n grafana 20231201_143000        # Force restore to grafana namespace

Backup Location: ${BACKUP_DIR}
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -l|--list)
            list_backups
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "${RESTORE_SOURCE}" ]; then
                RESTORE_SOURCE="$1"
            else
                log_error "Multiple sources specified"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Run main function
main