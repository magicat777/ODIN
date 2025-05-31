#!/bin/bash

# ODIN Dashboard Backup Script
# This script backs up all Grafana dashboards from ConfigMaps

set -euo pipefail

NAMESPACE="monitoring"
BACKUP_DIR="/home/magicat777/projects/ODIN/backups/dashboards"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

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

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}"
}

# Get all dashboard ConfigMaps
get_dashboard_configmaps() {
    log_info "Finding dashboard ConfigMaps in namespace ${NAMESPACE}"
    kubectl get configmaps -n "${NAMESPACE}" \
        -l grafana_dashboard=1 \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""
}

# Backup individual dashboard
backup_dashboard() {
    local cm_name="$1"
    local output_file="${BACKUP_PATH}/${cm_name}.yaml"
    
    log_info "Backing up dashboard: ${cm_name}"
    
    if kubectl get configmap "${cm_name}" -n "${NAMESPACE}" -o yaml > "${output_file}" 2>/dev/null; then
        log_success "Saved: ${output_file}"
        return 0
    else
        log_error "Failed to backup: ${cm_name}"
        return 1
    fi
}

# Create backup manifest
create_backup_manifest() {
    local manifest_file="${BACKUP_PATH}/backup-manifest.json"
    local dashboard_count=$(find "${BACKUP_PATH}" -name "*.yaml" | wc -l)
    
    log_info "Creating backup manifest"
    
    cat > "${manifest_file}" << EOF
{
  "backup_info": {
    "timestamp": "${TIMESTAMP}",
    "date": "$(date -Iseconds)",
    "namespace": "${NAMESPACE}",
    "dashboard_count": ${dashboard_count},
    "backup_path": "${BACKUP_PATH}",
    "kubernetes_version": "$(kubectl version --short --client | grep Client | cut -d' ' -f3)",
    "cluster_info": "$(kubectl cluster-info | head -1 | sed 's/.*https:\/\///' | sed 's/:.*//')"
  },
  "dashboards": [
$(find "${BACKUP_PATH}" -name "*.yaml" -not -name "backup-manifest.json" | sed 's/.*\///' | sed 's/\.yaml$//' | sed 's/^/    "/' | sed 's/$/"/' | paste -sd, -)
  ]
}
EOF
    
    log_success "Backup manifest created: ${manifest_file}"
}

# Create backup archive
create_backup_archive() {
    local archive_file="${BACKUP_DIR}/odin-dashboards-${TIMESTAMP}.tar.gz"
    
    log_info "Creating backup archive"
    
    cd "${BACKUP_DIR}"
    tar -czf "odin-dashboards-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"
    
    if [ -f "${archive_file}" ]; then
        log_success "Backup archive created: ${archive_file}"
        log_info "Archive size: $(du -h "${archive_file}" | cut -f1)"
    else
        log_error "Failed to create backup archive"
        return 1
    fi
}

# Cleanup old backups (keep last 10)
cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping latest 10)"
    
    cd "${BACKUP_DIR}"
    ls -1t *.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
    ls -1t -d */ 2>/dev/null | tail -n +11 | xargs -r rm -rf
    
    local remaining=$(ls -1 *.tar.gz 2>/dev/null | wc -l)
    log_info "Backup archives remaining: ${remaining}"
}

# Verify kubectl access
verify_kubectl_access() {
    log_info "Verifying kubectl access to namespace ${NAMESPACE}"
    
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        log_error "Cannot access namespace ${NAMESPACE}"
        exit 1
    fi
    
    if ! kubectl auth can-i get configmaps -n "${NAMESPACE}" >/dev/null 2>&1; then
        log_error "Insufficient permissions to read ConfigMaps in ${NAMESPACE}"
        exit 1
    fi
    
    log_success "kubectl access verified"
}

# Main backup function
main() {
    log_info "Starting ODIN Dashboard Backup"
    log_info "Timestamp: ${TIMESTAMP}"
    
    verify_kubectl_access
    create_backup_dir
    
    # Get dashboard ConfigMaps
    local dashboard_cms
    dashboard_cms=$(get_dashboard_configmaps)
    
    if [ -z "${dashboard_cms}" ]; then
        log_warning "No dashboard ConfigMaps found with label grafana_dashboard=1"
        exit 0
    fi
    
    log_info "Found dashboard ConfigMaps: ${dashboard_cms}"
    
    # Backup each dashboard
    local success_count=0
    local total_count=0
    
    for cm in ${dashboard_cms}; do
        ((total_count++))
        if backup_dashboard "${cm}"; then
            ((success_count++))
        fi
    done
    
    log_info "Backup progress: ${success_count}/${total_count} dashboards"
    
    if [ "${success_count}" -eq 0 ]; then
        log_error "No dashboards were successfully backed up"
        exit 1
    fi
    
    create_backup_manifest
    create_backup_archive
    cleanup_old_backups
    
    log_success "Dashboard backup completed successfully"
    log_info "Backed up ${success_count} dashboards to ${BACKUP_PATH}"
    log_info "Archive: ${BACKUP_DIR}/odin-dashboards-${TIMESTAMP}.tar.gz"
}

# Show help
show_help() {
    cat << EOF
ODIN Dashboard Backup Script

Usage: $0 [OPTIONS]

This script backs up all Grafana dashboard ConfigMaps from the monitoring namespace.

Options:
  -h, --help     Show this help message
  -n, --namespace NAMESPACE   Specify namespace (default: monitoring)

Examples:
  $0                          # Backup dashboards from monitoring namespace
  $0 -n grafana              # Backup dashboards from grafana namespace

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
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main