# ML Anomaly Detection User Guide

## Overview

The ODIN ML Anomaly Detection system uses machine learning algorithms to automatically detect unusual patterns in your metrics without manual threshold configuration.

## Architecture

- **Anomaly Detector Service**: Python-based service that queries Prometheus metrics
- **Algorithms**: Isolation Forest for complex patterns, Statistical methods for simple metrics  
- **Model Storage**: Persistent storage for trained models
- **Integration**: Exposes anomaly scores as Prometheus metrics

## Deployment

```bash
# Deploy the complete system
/home/magicat777/projects/ODIN/scripts/deploy-anomaly-detection.sh
```

## Monitored Metrics

1. **GPU Metrics** (Isolation Forest)
   - `nvidia_gpu_temperature_celsius` - Temperature anomalies
   - `node_gpu_power_watts` - Power consumption anomalies

2. **System Metrics** (Statistical)
   - `node_memory_MemAvailable_bytes` - Memory usage patterns
   - `rate(node_cpu_seconds_total[5m])` - CPU usage anomalies

3. **Network Metrics** (Isolation Forest)
   - `rate(node_network_receive_bytes_total[5m])` - Network traffic patterns

4. **API Metrics** (Statistical)
   - `claude_code_api_requests_total` - API usage anomalies

## Understanding Anomaly Scores

- **Score Range**: 0-100
  - 0-40: Normal behavior
  - 40-60: Slight deviation
  - 60-80: Warning level anomaly
  - 80-100: Critical anomaly

## Accessing Results

### Grafana Dashboard
Navigate to: http://localhost:31494/d/anomaly-detection

### Prometheus Queries
```promql
# All anomaly scores
anomaly_score

# Specific metric anomaly
anomaly_score{metric_name="nvidia_gpu_temperature_celsius"}

# High anomalies only
anomaly_score > 80

# Dynamic thresholds
anomaly_threshold
```

### Command Line
```bash
# Check all anomaly scores
kubectl exec -n monitoring deployment/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=anomaly_score' | jq

# Check detector health
kubectl logs -n monitoring -l app=anomaly-detector --tail=20
```

## Alert Rules

### Configured Alerts
- **HighAnomalyScore**: Score > 80 for 5 minutes
- **CriticalAnomalyScore**: Score > 95 for 2 minutes
- **GPUTemperatureAnomaly**: GPU temp anomaly with high temperature
- **MultipleAnomaliesDetected**: 3+ metrics anomalous simultaneously

### Alert Actions
When alerts fire:
1. Check the specific metric in Grafana
2. Review recent changes or deployments
3. Investigate correlated anomalies
4. Check system logs for errors

## Model Management

### Model Updates
- Models auto-update every 6 hours
- Training uses last 7 days of data
- Models persist across restarts

### Manual Model Reset
```bash
# Delete stored models to force retraining
kubectl exec -n monitoring -l app=anomaly-detector -- rm -rf /models/*
kubectl rollout restart deployment/anomaly-detector -n monitoring
```

## Tuning Sensitivity

Edit the anomaly detector ConfigMap to adjust sensitivity:

```yaml
# Lower value = more sensitive (more anomalies detected)
'sensitivity': 0.05,  # For Isolation Forest

# Higher value = less sensitive 
'z_threshold': 3,     # For Statistical method
```

## Troubleshooting

### No Anomaly Scores
1. Check if metrics exist: `kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=up'`
2. Verify detector is running: `kubectl get pods -n monitoring -l app=anomaly-detector`
3. Check logs: `kubectl logs -n monitoring -l app=anomaly-detector`

### High False Positives
- Increase sensitivity values
- Allow more training time (24-48 hours)
- Check for legitimate pattern changes

### Missing Metrics
- Ensure source metrics are being collected
- Verify metric names match exactly
- Check Prometheus scrape configuration

## Best Practices

1. **Initial Training**: Allow 24-48 hours for accurate baselines
2. **Regular Monitoring**: Check anomaly dashboard daily
3. **Alert Tuning**: Adjust thresholds based on false positive rate
4. **Correlation**: Look for multiple anomalies together
5. **Documentation**: Document when anomalies are expected (deployments, maintenance)

## Future Enhancements

- LSTM models for complex time series
- Automatic correlation analysis
- Predictive anomaly forecasting
- Custom metric support via API