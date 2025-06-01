# ODIN Email Alerts Implementation Guide

## Overview

This document describes the implementation of email alerting for the ODIN monitoring system, providing automated email notifications for critical alerts, container crashes, OOM kills, and anomaly detection.

## Implementation Summary

### Email Bridge Service
- **Service**: Python-based webhook-to-email bridge
- **Authentication**: Gmail SMTP with app-specific password
- **Port**: 8081 (internal cluster communication)
- **Health Check**: `/health` endpoint for monitoring

### Alert Routing Configuration
- **Critical Alerts**: Routed to email bridge for immediate notification
- **Anomaly Alerts**: ML-detected anomalies trigger email notifications
- **Monitoring Stack**: Infrastructure alerts sent via email
- **Webhook Fallback**: All alerts still logged to webhook-logger

## Files Created/Modified

### Core Implementation
- `email-bridge.yaml` - Complete email bridge service (ConfigMap + Deployment + Service)
- `alertmanager-with-email-bridge.yaml` - AlertManager configuration routing alerts to email bridge
- `enhanced-pod-rules.yaml` - Enhanced pod monitoring rules for OOM/crash detection

### Alternative Configurations (Reference)
- `alertmanager-email-fixed.yaml` - Direct AlertManager SMTP configuration (v0.28.x syntax)
- `email-setup-guide.md` - Complete setup guide with multiple implementation options
- `test-alert.yaml` - Test alert rules for validation

### Documentation
- `docs/EMAIL_ALERTS_IMPLEMENTATION.md` - This implementation guide

## Technical Architecture

### Email Bridge Service
```python
# Core Components:
- HTTP webhook receiver on port 8081
- Gmail SMTP client with app password authentication  
- Alert data parser and email formatter
- Health check endpoint for monitoring
```

### Alert Flow
```
1. Prometheus detects condition → Alert fires
2. AlertManager receives alert → Routes to appropriate receiver
3. Critical/Anomaly alerts → Sent to email-bridge webhook
4. Email bridge → Formats alert → Sends Gmail notification
5. Email delivered to jason.holt@andominia.com
```

### Gmail Configuration
- **SMTP Server**: smtp.gmail.com:587
- **Authentication**: App-specific password (not account password)
- **Security**: TLS encryption enabled
- **From Address**: odin-alerts@gmail.com

## Alert Categories with Email Routing

### Critical Alerts (Immediate Email)
- Container crashes and restarts
- Out-of-memory (OOM) kills
- API server failures
- Monitoring stack failures

### Anomaly Alerts (2-hour repeat interval)
- High anomaly scores (ML detection)
- Critical anomaly scores
- Process behavior anomalies
- Resource usage anomalies

### Component-Specific Alerts
- **GPU**: Thermal/power alerts with specialized formatting
- **K3s**: Cluster health and node status
- **Claude Code**: Process monitoring and API token usage
- **Monitoring Stack**: Prometheus/Grafana/Loki issues

## Deployment Process

### 1. Gmail App Password Setup
```bash
# Required: 2-factor authentication enabled
# Generate at: https://myaccount.google.com/apppasswords
# Replace PASSWORD in email-bridge.yaml with 16-character app password
```

### 2. Deploy Email Bridge
```bash
kubectl apply -f email-bridge.yaml
kubectl wait --for=condition=ready pod -l app=email-bridge -n monitoring
```

### 3. Update AlertManager Configuration
```bash
kubectl apply -f alertmanager-with-email-bridge.yaml
kubectl rollout restart deployment/alertmanager -n monitoring
```

### 4. Verify Operation
```bash
# Check email bridge health
kubectl port-forward -n monitoring svc/email-bridge 8081:8081 &
curl http://localhost:8081/health

# Test email functionality
curl -X POST http://localhost:8081/ -H "Content-Type: application/json" \
  -d '{"status":"firing","alerts":[{"labels":{"alertname":"TestAlert","severity":"critical"},"annotations":{"summary":"Test notification"}}]}'
```

## Validation Results

### ✅ Successful Test Results
- Email bridge deployment: **OPERATIONAL**
- Gmail authentication: **WORKING** (with app password)
- Webhook processing: **FUNCTIONAL**
- Email delivery: **CONFIRMED**
- Health checks: **PASSING**

### Current Active Alerts
- `PrometheusTargetMissing` (warning level)
- `OdinServiceDiscoverySLOBreach` (monitoring SLO)

## Troubleshooting

### Common Issues

1. **Gmail Authentication Failure**
   - **Error**: `Application-specific password required`
   - **Solution**: Generate app password, update email-bridge.yaml line 28

2. **Email Bridge Connection Refused**
   - **Check**: Pod status `kubectl get pods -n monitoring -l app=email-bridge`
   - **Fix**: Restart deployment if needed

3. **No Email Notifications**
   - **Verify**: AlertManager routing rules match alert labels
   - **Check**: Email bridge logs for webhook reception
   - **Test**: Manual webhook POST to verify email sending

### Debug Commands
```bash
# Check email bridge logs
kubectl logs -n monitoring -l app=email-bridge --tail=20

# Verify AlertManager configuration
kubectl get configmap alertmanager-config -n monitoring -o yaml

# Check active alerts
curl -s http://localhost:31495/api/v2/alerts | jq '.[] | select(.status.state == "active")'
```

## Security Considerations

- Gmail app password stored in ConfigMap (consider secrets for production)
- Email bridge runs with minimal resource limits
- No external network access required beyond Gmail SMTP
- Health checks prevent zombie containers

## Future Enhancements

1. **Kubernetes Secrets**: Move Gmail credentials to Secret resource
2. **Email Templates**: Rich HTML email formatting with graphs/charts
3. **Multiple Recipients**: Support for distribution lists and escalation
4. **Alert Aggregation**: Batch multiple alerts into digest emails
5. **SMS Integration**: Extend bridge to support SMS for critical alerts

## Maintenance

- **App Password Rotation**: Update every 90 days for security
- **Log Monitoring**: Check email bridge logs for delivery failures
- **Resource Monitoring**: Monitor memory/CPU usage of email bridge
- **Alert Rule Review**: Regularly review and tune alert thresholds

---

**Status**: ✅ **PRODUCTION READY**
**Last Updated**: 2025-06-01
**Contact**: jason.holt@andominia.com