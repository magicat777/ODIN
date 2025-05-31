#!/bin/bash

# Simple ODIN Dashboard Backup Script
set -e

NAMESPACE="monitoring"
BACKUP_DIR="/home/magicat777/projects/ODIN/backups/dashboards"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

echo "Starting dashboard backup..."
echo "Timestamp: ${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Get all dashboard ConfigMaps
DASHBOARDS=$(kubectl get configmaps -n "${NAMESPACE}" -l grafana_dashboard=1 -o jsonpath='{.items[*].metadata.name}')

if [ -z "${DASHBOARDS}" ]; then
    echo "No dashboard ConfigMaps found"
    exit 1
fi

echo "Found dashboards: ${DASHBOARDS}"

# Backup each dashboard
SUCCESS_COUNT=0
for dashboard in ${DASHBOARDS}; do
    echo "Backing up: ${dashboard}"
    if kubectl get configmap "${dashboard}" -n "${NAMESPACE}" -o yaml > "${BACKUP_PATH}/${dashboard}.yaml"; then
        echo "  ✓ Saved: ${dashboard}.yaml"
        ((SUCCESS_COUNT++))
    else
        echo "  ✗ Failed: ${dashboard}"
    fi
done

# Create manifest
cat > "${BACKUP_PATH}/backup-info.json" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "namespace": "${NAMESPACE}",
  "dashboard_count": ${SUCCESS_COUNT},
  "dashboards": $(echo "${DASHBOARDS}" | tr ' ' '\n' | jq -R -s 'split("\n")[:-1]')
}
EOF

# Create archive
cd "${BACKUP_DIR}"
tar -czf "odin-dashboards-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"

echo "Backup completed: ${SUCCESS_COUNT} dashboards"
echo "Archive: ${BACKUP_DIR}/odin-dashboards-${TIMESTAMP}.tar.gz"
echo "Size: $(du -h "odin-dashboards-${TIMESTAMP}.tar.gz" | cut -f1)"

# Cleanup old backups (keep last 5)
ls -1t *.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
echo "Cleanup completed, keeping latest 5 backups"