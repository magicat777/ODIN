# ODIN Dashboard Backup & Restore

This document describes the dashboard backup and restore system for the ODIN monitoring stack.

## Overview

The ODIN dashboard backup system provides automated backup and restore capabilities for all Grafana dashboards stored as Kubernetes ConfigMaps. This ensures dashboard configurations are preserved and can be restored in case of system failure or accidental deletion.

## Scripts Location

- **Backup Script**: `/home/magicat777/projects/ODIN/scripts/dashboard-backup-simple.sh`
- **Restore Script**: `/home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh`
- **Backup Directory**: `/home/magicat777/projects/ODIN/backups/dashboards/`

## Backup System

### Automated Backup

The backup script automatically:
1. Discovers all dashboard ConfigMaps with label `grafana_dashboard=1`
2. Exports each dashboard as a YAML file
3. Creates a backup manifest with metadata
4. Compresses everything into a timestamped archive
5. Maintains cleanup of old backups

### Running a Backup

```bash
# Create a backup of all dashboards
/home/magicat777/projects/ODIN/scripts/dashboard-backup-simple.sh
```

### Backup Output

```
=== ODIN Dashboard Backup ===
Timestamp: 20250528_111854
Found dashboards: claude-code-dashboard comprehensive-logs-dashboard simple-logs-dashboard system-overview-dashboard
Backing up: claude-code-dashboard
  ✓ Saved: claude-code-dashboard.yaml
Backing up: comprehensive-logs-dashboard
  ✓ Saved: comprehensive-logs-dashboard.yaml
Backing up: simple-logs-dashboard
  ✓ Saved: simple-logs-dashboard.yaml
Backing up: system-overview-dashboard
  ✓ Saved: system-overview-dashboard.yaml
Creating backup manifest...
Creating archive...

=== Backup Complete ===
Dashboards backed up: 4
Archive: /home/magicat777/projects/ODIN/backups/dashboards/odin-dashboards-20250528_111854.tar.gz
Size: 8.0K
```

## Restore System

### List Available Backups

```bash
# Show available backups
/home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh
```

### Restore from Backup

```bash
# Restore from timestamp
/home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh 20250528_111854

# Restore from archive file
/home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh /path/to/backup.tar.gz
```

### Restore Process

1. **Extraction**: Archive is extracted to temporary directory
2. **Validation**: Backup contents are validated
3. **Confirmation**: User confirms restore operation
4. **Application**: Each dashboard ConfigMap is applied to Kubernetes
5. **Grafana Restart**: Grafana is restarted to reload dashboards
6. **Cleanup**: Temporary files are removed

## File Structure

### Backup Archive Contents

```
odin-dashboards-20250528_111854.tar.gz
└── 20250528_111854/
    ├── backup-info.txt                    # Backup metadata
    ├── claude-code-dashboard.yaml         # Claude API monitoring dashboard
    ├── comprehensive-logs-dashboard.yaml  # Log analysis dashboard
    ├── simple-logs-dashboard.yaml         # Simple log viewer
    └── system-overview-dashboard.yaml     # System overview dashboard
```

### Backup Metadata

The `backup-info.txt` file contains:
```
ODIN Dashboard Backup
Timestamp: 20250528_111854
Date: Wed May 28 11:18:54 AM PDT 2025
Namespace: monitoring
Dashboard Count: 4
Dashboards: claude-code-dashboard comprehensive-logs-dashboard simple-logs-dashboard system-overview-dashboard
```

## Automation

### Scheduled Backups

To automate dashboard backups, add to crontab:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/magicat777/projects/ODIN/scripts/dashboard-backup-simple.sh >> /var/log/odin-backup.log 2>&1
```

### Pre-Change Backups

Before making dashboard changes:

```bash
# Create backup before changes
/home/magicat777/projects/ODIN/scripts/dashboard-backup-simple.sh

# Make your changes...

# If something goes wrong, restore from backup
/home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh TIMESTAMP
```

## Disaster Recovery

### Complete Dashboard Loss

1. **Check Available Backups**:
   ```bash
   /home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh
   ```

2. **Restore Latest Backup**:
   ```bash
   /home/magicat777/projects/ODIN/scripts/dashboard-restore-simple.sh LATEST_TIMESTAMP
   ```

3. **Verify Restoration**:
   ```bash
   kubectl get configmaps -n monitoring -l grafana_dashboard=1
   ```

### Individual Dashboard Recovery

1. **Extract Specific Dashboard**:
   ```bash
   cd /tmp
   tar -xzf /home/magicat777/projects/ODIN/backups/dashboards/odin-dashboards-TIMESTAMP.tar.gz
   kubectl apply -f TIMESTAMP/DASHBOARD_NAME.yaml
   ```

2. **Restart Grafana**:
   ```bash
   kubectl rollout restart deployment/grafana -n monitoring
   ```

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   ```bash
   # Make scripts executable
   chmod +x /home/magicat777/projects/ODIN/scripts/dashboard-*.sh
   ```

2. **kubectl Access Issues**:
   ```bash
   # Verify kubectl access
   kubectl get configmaps -n monitoring
   ```

3. **Backup Directory Issues**:
   ```bash
   # Create backup directory
   mkdir -p /home/magicat777/projects/ODIN/backups/dashboards
   ```

4. **Grafana Not Reloading**:
   ```bash
   # Manually restart Grafana
   kubectl rollout restart deployment/grafana -n monitoring
   kubectl wait --for=condition=ready pod -l app=grafana -n monitoring
   ```

### Verification Commands

```bash
# Check dashboard ConfigMaps
kubectl get configmaps -n monitoring -l grafana_dashboard=1

# Check Grafana pods
kubectl get pods -n monitoring -l app=grafana

# Check backup files
ls -la /home/magicat777/projects/ODIN/backups/dashboards/

# Verify archive contents
tar -tzf /home/magicat777/projects/ODIN/backups/dashboards/odin-dashboards-TIMESTAMP.tar.gz
```

## Best Practices

1. **Regular Backups**: Schedule automated daily backups
2. **Pre-Change Backups**: Always backup before making changes
3. **Test Restores**: Periodically test restore procedures
4. **Monitor Backup Size**: Watch for unusual growth in backup sizes
5. **Backup Rotation**: Keep reasonable number of backups (default: 5)
6. **Documentation**: Document any custom dashboard modifications

## Integration with ODIN

The backup/restore system integrates with the ODIN monitoring stack:

- **Monitored Components**: All ODIN dashboards are backed up
- **Kubernetes Native**: Uses kubectl and ConfigMaps
- **Namespace Aware**: Operates within the monitoring namespace
- **Grafana Integration**: Automatically restarts Grafana after restore

## Security Considerations

- Backup files contain dashboard configurations (not sensitive data)
- Scripts require kubectl access to monitoring namespace
- Backups are stored locally (consider encryption for production)
- No external network access required