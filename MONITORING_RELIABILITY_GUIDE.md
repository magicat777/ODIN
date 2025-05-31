# ODIN Monitoring Stack Reliability Guide

## Overview
This guide ensures your ODIN monitoring stack remains operational and resilient.

## Key Reliability Features Implemented

### 1. Health Checks & Probes
- **Liveness Probes**: Automatically restart unhealthy containers
- **Readiness Probes**: Prevent traffic to unready pods
- **Health Check CronJob**: Runs every 5 minutes to verify all services

### 2. Automated Recovery
- **CronJob Health Checker**: `/home/magicat777/projects/ODIN/k8s/monitoring-reliability.yaml`
  - Checks: Prometheus, Grafana, Loki, AlertManager
  - Auto-restarts: Failed deployments
  - Schedule: Every 5 minutes

### 3. Resource Management
- **CPU/Memory Limits**: Prevent resource exhaustion
- **Persistent Storage**: Data survives pod restarts
- **Proper RBAC**: Secure service access

### 4. Self-Monitoring Dashboard
- **Location**: Grafana > Monitoring Health folder
- **Metrics**: Service uptime, restarts, resource usage, alerts

## Daily Operations

### Check System Health
```bash
# Overall status
kubectl get pods -n monitoring

# Check health check logs
kubectl logs -n monitoring -l job-name=monitoring-healthcheck --tail=20

# Resource usage
kubectl top pods -n monitoring
```

### Manual Recovery Commands
```bash
# Restart individual services
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout restart deployment/loki -n monitoring
kubectl rollout restart deployment/alertmanager -n monitoring

# Check service health
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/-/healthy

kubectl port-forward -n monitoring svc/grafana 3000:3000 &
curl http://localhost:3000/api/health
```

## Monitoring What Matters

### Critical Metrics to Watch
1. **Service Uptime**: `up{job=~"prometheus|grafana|loki|alertmanager"}`
2. **Pod Restarts**: `kube_pod_container_status_restarts_total{namespace="monitoring"}`
3. **Resource Usage**: CPU/Memory limits
4. **Alert Status**: Active firing alerts

### Alert Thresholds
- **High Priority**: Service down > 1 minute
- **Medium Priority**: High resource usage > 5 minutes  
- **Low Priority**: Informational alerts

## Troubleshooting Common Issues

### 1. Prometheus Down
```bash
# Check logs
kubectl logs -n monitoring deployment/prometheus

# Check persistent volume
kubectl get pv,pvc -n monitoring

# Common fix: Storage permission issues
kubectl delete pod -n monitoring -l app=prometheus
```

### 2. Grafana Login Issues
```bash
# Reset admin password
kubectl exec -n monitoring deployment/grafana -- grafana-cli admin reset-admin-password admin

# Check datasource connection
kubectl exec -n monitoring deployment/grafana -- curl -s http://prometheus:9090/-/healthy
```

### 3. Missing Metrics
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/api/v1/targets

# Restart metric collectors
kubectl rollout restart daemonset/node-exporter -n monitoring
kubectl rollout restart deployment/kube-state-metrics -n monitoring
```

### 4. Disk Space Issues
```bash
# Check storage usage
kubectl exec -n monitoring deployment/prometheus -- df -h /prometheus
kubectl exec -n monitoring deployment/loki -- df -h /loki

# Clean old data (if needed)
kubectl exec -n monitoring deployment/prometheus -- find /prometheus -name "*.db" -mtime +30 -delete
```

## Backup & Recovery

### Data Locations
- **Prometheus**: `/var/lib/odin/prometheus`
- **Grafana**: `/var/lib/odin/grafana` 
- **Loki**: `/var/lib/odin/loki`
- **AlertManager**: `/var/lib/odin/alertmanager`

### Backup Commands
```bash
# Create backup
sudo tar -czf odin-backup-$(date +%Y%m%d).tar.gz /var/lib/odin/

# Restore from backup
sudo tar -xzf odin-backup-YYYYMMDD.tar.gz -C /
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/grafana -n monitoring
```

## Performance Optimization

### Resource Tuning
```bash
# Monitor resource usage
kubectl top pods -n monitoring
kubectl describe nodes

# Adjust resource limits if needed
kubectl edit deployment prometheus -n monitoring
```

### Storage Management
```bash
# Check retention policies
kubectl exec -n monitoring deployment/prometheus -- cat /etc/prometheus/prometheus.yml | grep retention

# Adjust retention (default: 30 days)
# Edit: storage.tsdb.retention.time=15d
```

## Alerting Best Practices

### Alert Routing
- **Critical**: Immediate notification
- **Warning**: Aggregated hourly
- **Info**: Daily digest

### Silence Management
```bash
# Access AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Visit: http://localhost:9093
```

## Monitoring Success Metrics

### Key Performance Indicators
- **Uptime**: >99.5% service availability
- **Query Performance**: <2s dashboard load time
- **Storage Growth**: <10GB/month data growth
- **Alert Noise**: <5 false positives/day

### Health Check Schedule
- **Real-time**: Kubernetes probes
- **Every 5 minutes**: Automated health check
- **Daily**: Resource usage review
- **Weekly**: Performance analysis
- **Monthly**: Capacity planning

## Emergency Procedures

### Complete Stack Recovery
```bash
# 1. Check cluster health
kubectl get nodes
kubectl get ns monitoring

# 2. Restart all services
kubectl delete pods -n monitoring --all

# 3. Wait for automatic recovery
kubectl wait --for=condition=Ready pods -n monitoring -l app=prometheus --timeout=300s

# 4. Verify functionality
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
```

### Data Recovery
```bash
# If persistent volumes are corrupted
kubectl get pv,pvc -n monitoring
kubectl patch pv <pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# Restore from backup
sudo rm -rf /var/lib/odin/*
sudo tar -xzf odin-backup-latest.tar.gz -C /
```

## Contact & Support

For issues with the ODIN monitoring stack:
1. Check this guide first
2. Review Grafana "Monitoring Health" dashboard
3. Check health check cron job logs
4. Consult project documentation in `/docs/`

Remember: The system is designed to self-heal. Most issues resolve automatically within 5-10 minutes.