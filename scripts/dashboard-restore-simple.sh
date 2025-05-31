#!/bin/bash

# ODIN Dashboard Restore Script (Simplified)
NAMESPACE="monitoring"
BACKUP_DIR="/home/magicat777/projects/ODIN/backups/dashboards"

show_help() {
    echo "Usage: $0 [TIMESTAMP|ARCHIVE_FILE]"
    echo ""
    echo "Available backups:"
    ls -1 "${BACKUP_DIR}"/odin-dashboards-*.tar.gz 2>/dev/null | sed 's/.*odin-dashboards-\(.*\)\.tar\.gz/  \1/' || echo "  No backups found"
    echo ""
    echo "Examples:"
    echo "  $0 20250528_111854"
    echo "  $0 /path/to/backup.tar.gz"
}

if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

SOURCE="$1"

# Determine source type
if [ -f "${SOURCE}" ]; then
    ARCHIVE_FILE="${SOURCE}"
elif [ -f "${BACKUP_DIR}/odin-dashboards-${SOURCE}.tar.gz" ]; then
    ARCHIVE_FILE="${BACKUP_DIR}/odin-dashboards-${SOURCE}.tar.gz"
else
    echo "Error: Source not found: ${SOURCE}"
    show_help
    exit 1
fi

echo "=== ODIN Dashboard Restore ==="
echo "Source: $(basename "${ARCHIVE_FILE}")"

# Extract to temp directory
TEMP_DIR="/tmp/odin-restore-$$"
mkdir -p "${TEMP_DIR}"

echo "Extracting archive..."
tar -xzf "${ARCHIVE_FILE}" -C "${TEMP_DIR}"

# Find extracted directory
EXTRACT_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "2*" | head -1)

if [ ! -d "${EXTRACT_DIR}" ]; then
    echo "Error: Could not find extracted backup directory"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

echo "Found backup directory: $(basename "${EXTRACT_DIR}")"

# List dashboards to restore
DASHBOARD_FILES=$(find "${EXTRACT_DIR}" -name "*.yaml" -not -name "backup-info.*")
DASHBOARD_COUNT=$(echo "${DASHBOARD_FILES}" | wc -l)

echo "Dashboards to restore: ${DASHBOARD_COUNT}"
for file in ${DASHBOARD_FILES}; do
    echo "  - $(basename "${file}" .yaml)"
done

# Confirm restore
echo ""
echo "This will apply ${DASHBOARD_COUNT} dashboard ConfigMaps to namespace '${NAMESPACE}'"
echo -n "Continue? [y/N]: "
read -r response

if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    echo "Restore cancelled"
    rm -rf "${TEMP_DIR}"
    exit 0
fi

# Restore dashboards
echo ""
echo "Restoring dashboards..."
SUCCESS_COUNT=0

for file in ${DASHBOARD_FILES}; do
    dashboard_name=$(basename "${file}" .yaml)
    echo "Restoring: ${dashboard_name}"
    
    if kubectl apply -f "${file}"; then
        echo "  ✓ Restored: ${dashboard_name}"
        ((SUCCESS_COUNT++))
    else
        echo "  ✗ Failed: ${dashboard_name}"
    fi
done

# Cleanup
rm -rf "${TEMP_DIR}"

echo ""
echo "=== Restore Complete ==="
echo "Dashboards restored: ${SUCCESS_COUNT}/${DASHBOARD_COUNT}"

if [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo "Restarting Grafana to reload dashboards..."
    kubectl rollout restart deployment/grafana -n "${NAMESPACE}"
    echo "Grafana restarted successfully"
fi