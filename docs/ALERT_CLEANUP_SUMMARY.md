# ODIN Alert Cleanup Summary

## Current Issues

1. **Duplicate Alert Rules**: Multiple ConfigMaps contain overlapping alert rules:
   - `odin-stack-alert-rules`: Contains PowerExporterDown, NodeExporterDown alerts
   - `power-exporter-alert-rules`: Also contains PowerExporterDown alert  
   - `gpu-alert-rules`: Contains GPUMetricsDown which checks the same `up{job="power-exporter"}` metric

2. **Target Mismatch**: Alerts are looking for the wrong target labels:
   - Alerts expect: `power-exporter:9402`, `node-exporter:9100`
   - Actual targets: `192.168.1.154:9402`, `192.168.1.154:9100`

3. **False Positive Memory Alert**: PrometheusHighMemoryUsage is alerting when memory is only at 18%

## Resolved Issues

1. **Prometheus Configuration**: Updated to include:
   - Loki scraping at `loki:3100`
   - Promtail scraping at `promtail:9080`
   - Host-based exporters using IP addresses

2. **Service Discovery**: Fixed host-based exporters to use direct IP addresses instead of Kubernetes service names

## Remaining Alerts

The following alerts are still firing due to duplicate rules:
- NodeExporterDown (from old rules checking wrong target)
- PowerExporterDown (from multiple ConfigMaps)
- GPUMetricsDown (checking wrong target)
- MonitoringStackDegraded (triggered by the above false alerts)

## Recommended Actions

1. **Consolidate Alert Rules**: 
   - Keep only the `odin-stack-alert-rules` for monitoring stack health
   - Remove duplicate alerts from other ConfigMaps
   - Ensure all alerts use the correct target labels

2. **Fix Memory Alert**: Update the PrometheusHighMemoryUsage alert to use a more accurate memory metric

3. **Remove Network Exporter Alert**: Since no network exporter pod exists, remove or comment out the NetworkExporterDown alert

## Current State

All services are actually healthy and running:
- Prometheus: ✅ Running
- Grafana: ✅ Running  
- Loki: ✅ Running
- Promtail: ✅ Running
- AlertManager: ✅ Running
- Node Exporter: ✅ Running (host-based)
- Power Exporter: ✅ Running (host-based)
- Claude Code Exporter: ✅ Running (host-based)

The alerts are false positives caused by configuration mismatches.