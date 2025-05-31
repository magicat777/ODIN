# Monitoring Stack Backup & Restore Guide

## Overview

The ODIN monitoring stack includes automated backup capabilities for Prometheus and Grafana data. Backups are performed daily at 2 AM and retained for 7 days.

## Backup Components

### What Gets Backed Up

1. **Prometheus Data**
   - Time-series metrics data
   - Write-ahead logs (WAL)
   - Alert states

2. **Grafana Data**
   - Dashboards
   - User preferences
   - Alert configurations
   - Data source configurations

3. **Kubernetes Configurations**
   - ConfigMaps
   - Secrets
   - PersistentVolumeClaims

### Backup Storage

Backups are stored in `/var/lib/odin/backups` with the following structure:
```
/var/lib/odin/backups/
├── prometheus/
│   └── YYYYMMDD_HHMMSS/
│       └── prometheus-data.tar.gz
├── grafana/
│   └── YYYYMMDD_HHMMSS/
│       └── grafana-data.tar.gz
└── configs/
    └── YYYYMMDD_HHMMSS/
        ├── configmaps.yaml
        ├── secrets.yaml
        ├── pvcs.yaml
        └── metadata.json
```

## Manual Backup

To perform a manual backup:

```bash
# Create and run a backup job
kubectl apply -f /home/magicat777/projects/ODIN/k8s/manual-backup-job.yaml

# Monitor backup progress
kubectl logs -f -n monitoring -l job-name=monitoring-backup-manual

# Check backup completion
kubectl get jobs -n monitoring
```

## Restore Procedure

### Prerequisites

1. Ensure the monitoring namespace exists:
   ```bash
   kubectl create namespace monitoring
   ```

2. Apply storage configurations:
   ```bash
   kubectl apply -f /home/magicat777/projects/ODIN/k8s/storage-class.yaml
   ```

### Restore Steps

1. **List Available Backups**
   ```bash
   ls -la /var/lib/odin/backups/configs/
   ```

2. **Create Restore Job**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: monitoring-restore-$(date +%s)
     namespace: monitoring
   spec:
     template:
       spec:
         serviceAccountName: monitoring-backup-sa
         containers:
         - name: restore
           image: bitnami/kubectl:latest
           command: ["/bin/bash", "/scripts/restore.sh", "YYYYMMDD_HHMMSS"]
           volumeMounts:
           - name: backup-storage
             mountPath: /backups
           - name: prometheus-data
             mountPath: /prometheus-data
           - name: grafana-data
             mountPath: /grafana-data
           - name: scripts
             mountPath: /scripts
         restartPolicy: OnFailure
         volumes:
         - name: backup-storage
           persistentVolumeClaim:
             claimName: monitoring-backup-pvc
         - name: prometheus-data
           persistentVolumeClaim:
             claimName: prometheus-pvc
         - name: grafana-data
           persistentVolumeClaim:
             claimName: grafana-pvc
         - name: scripts
           configMap:
             name: backup-scripts
             defaultMode: 0755
   EOF
   ```

3. **Restart Services**
   ```bash
   kubectl rollout restart deployment/prometheus -n monitoring
   kubectl rollout restart deployment/grafana -n monitoring
   ```

## Backup Verification

To verify backup integrity:

1. **Check Backup Sizes**
   ```bash
   du -sh /var/lib/odin/backups/*/*
   ```

2. **Test Restore in Staging**
   - Create a test namespace
   - Restore data to test PVCs
   - Verify metrics and dashboards

## Disaster Recovery

In case of complete system failure:

1. **Reinstall K3s**
   ```bash
   /home/magicat777/projects/ODIN/scripts/quickstart.sh
   ```

2. **Restore Configurations**
   ```bash
   kubectl apply -f /var/lib/odin/backups/configs/LATEST/configmaps.yaml
   kubectl apply -f /var/lib/odin/backups/configs/LATEST/secrets.yaml
   ```

3. **Restore Data**
   - Follow the restore procedure above

## Backup Monitoring

Monitor backup health:

```bash
# Check CronJob status
kubectl get cronjobs -n monitoring

# View recent backup jobs
kubectl get jobs -n monitoring | grep backup

# Check backup storage usage
df -h /var/lib/odin/backups
```

## Troubleshooting

### Common Issues

1. **Backup Job Fails**
   - Check pod logs: `kubectl logs -n monitoring <backup-pod>`
   - Verify storage permissions: `ls -la /var/lib/odin/backups`
   - Check PVC availability: `kubectl get pvc -n monitoring`

2. **Restore Fails**
   - Ensure PVCs exist before restore
   - Verify backup file integrity
   - Check namespace and RBAC permissions

3. **Storage Full**
   - Manually clean old backups
   - Adjust retention policy in backup script
   - Increase PV size if needed

## Best Practices

1. **Regular Testing**
   - Test restore procedure monthly
   - Verify backup completeness
   - Document any issues

2. **Off-site Backups**
   - Copy critical backups to external storage
   - Consider cloud backup solutions
   - Maintain backup rotation policy

3. **Monitoring**
   - Set up alerts for backup failures
   - Monitor backup storage usage
   - Track backup/restore metrics