# ML Anomaly Detection Dashboard Fix Summary

## Date: 2025-05-30

### Issue
The ML Anomaly Detection dashboard was looking for incorrect metric names that didn't match what the anomaly detector was actually producing.

### Changes Made

1. **GPU Power Metric**
   - Changed: `nvidia_gpu_power_draw_watts` → `node_gpu_power_watts`
   - Panel ID: 3 (GPU Power Draw Anomaly Score)

2. **CPU Usage Metric**
   - Changed: `node_cpu_seconds_total` → `cpu_usage_percent`
   - Panel ID: 5 (CPU Usage Anomaly Score)

3. **Network Traffic Metric**
   - Changed: `rate(node_network_receive_bytes_total[5m])` → `network_receive_rate`
   - Panel ID: 6 (Network Traffic Anomaly Score)

### Metrics Verified
The following metrics are confirmed to be produced by the anomaly-detector-v2:

- `anomaly_score{metric_name="nvidia_gpu_temperature_celsius"}` - GPU temperature anomalies
- `anomaly_score{metric_name="node_gpu_power_watts"}` - GPU power anomalies
- `anomaly_score{metric_name="node_memory_MemAvailable_bytes"}` - Memory availability anomalies
- `anomaly_score{metric_name="cpu_usage_percent"}` - CPU usage anomalies
- `anomaly_score{metric_name="network_receive_rate"}` - Network traffic anomalies
- `anomaly_detector_health` - Health status of the detector
- `anomaly_model_updates_total` - Counter for model updates
- `anomaly_threshold` - Dynamic thresholds (upper/lower bounds)

### Implementation
- Updated the ConfigMap `anomaly-detection-dashboard` in the monitoring namespace
- Restarted Grafana deployment to reload the dashboard
- All referenced metrics have been verified to exist in Prometheus

### Result
The dashboard should now correctly display anomaly scores for all monitored metrics with the proper metric names that match the anomaly detector's output.