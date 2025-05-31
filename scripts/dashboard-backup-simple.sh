#!/bin/bash

# ODIN Dashboard Backup Script (Simplified)
NAMESPACE="monitoring"
BACKUP_DIR="/home/magicat777/projects/ODIN/backups/dashboards"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

echo "=== ODIN Dashboard Backup ==="
echo "Timestamp: ${TIMESTAMP}"

mkdir -p "${BACKUP_PATH}"

# Get all dashboard ConfigMaps
DASHBOARDS=$(kubectl get configmaps -n "${NAMESPACE}" -l grafana_dashboard=1 -o jsonpath='{.items[*].metadata.name}')

echo "Found dashboards: ${DASHBOARDS}"

# Backup each dashboard
SUCCESS_COUNT=0
for dashboard in ${DASHBOARDS}; do
    echo "Backing up: ${dashboard}"
    kubectl get configmap "${dashboard}" -n "${NAMESPACE}" -o yaml > "${BACKUP_PATH}/${dashboard}.yaml"
    echo "  ✓ Saved: ${dashboard}.yaml"
    ((SUCCESS_COUNT++))
done

# Create simple manifest
echo "Creating backup manifest..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
ODIN Dashboard Backup
Timestamp: ${TIMESTAMP}
Date: $(date)
Namespace: ${NAMESPACE}
Dashboard Count: ${SUCCESS_COUNT}
Dashboards: ${DASHBOARDS}
EOF

# Create archive
echo "Creating archive..."
cd "${BACKUP_DIR}"
tar -czf "odin-dashboards-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"

echo ""
echo "=== Backup Complete ==="
echo "Dashboards backed up: ${SUCCESS_COUNT}"
echo "Archive: ${BACKUP_DIR}/odin-dashboards-${TIMESTAMP}.tar.gz"
echo "Size: $(du -h "odin-dashboards-${TIMESTAMP}.tar.gz" | cut -f1)"

# List current backups
echo ""
echo "Current backups:"
ls -lh *.tar.gz 2>/dev/null | tail -5