# ODIN Rollup Dashboard Guide

## Overview

The ODIN Rollup Dashboard provides a comprehensive single-pane-of-glass view of the entire monitoring stack. It's designed for administrators to quickly assess system health, identify issues, and monitor trends.

## Dashboard Access

The dashboard should now be available in Grafana under:
- **Name**: ODIN Rollup Dashboard
- **UID**: odin-rollup
- **Tags**: odin, rollup, monitoring

## Key Features

### 1. Stack Health Matrix (Top Row)
A visual status indicator showing UP/DOWN status for all ODIN components:
- Prometheus, Grafana, Loki, AlertManager
- Node Exporter, GPU Power Exporter, cAdvisor
- Kube State Metrics, Promtail, Claude Code Exporter

**🟢 Green = UP | 🔴 Red = DOWN**

### 2. Critical Metrics Row
Four key indicators for immediate attention:
- **🚨 Active Alerts**: Count of currently firing alerts
- **💻 CPU Usage**: System-wide CPU utilization percentage
- **🧠 Memory Usage**: System memory utilization percentage  
- **💾 Disk Usage**: Root filesystem usage percentage

Color coding:
- Green: Normal operation
- Yellow: Warning threshold
- Orange: High usage
- Red: Critical levels

### 3. Resource Utilization Trends
Two time-series graphs showing:
- **System Resources**: CPU, Memory, and GPU utilization over time
- **Thermal & Power**: GPU/CPU temperatures and GPU power draw

### 4. Alert Analysis
- **Active Alerts Table**: Detailed view of all firing alerts with severity
- **Log Level Distribution**: Pie chart showing ERROR/WARN/INFO/DEBUG ratios

### 5. Operational Metrics
Six stat panels showing:
- **Prometheus Metrics**: Total metric count
- **Loki Ingestion Rate**: Logs per second
- **Running Pods**: Pod count in monitoring namespace
- **Claude Tokens Used**: Total API token consumption
- **Pod Restarts/hr**: Container restart rate
- **System Uptime**: Time since last boot

### 6. I/O Performance
Two graphs monitoring:
- **Network I/O**: RX/TX rates for all network interfaces
- **Disk I/O**: Read/Write rates for all disks

### 7. Error Log Stream
Live tail of error logs from all monitoring components, filtered for:
- ERROR, FAIL, CRASH, PANIC, FATAL keywords

## Usage Guidelines

### Daily Health Checks
1. Check the Stack Health Matrix - all should be green
2. Review Active Alerts count - investigate if > 0
3. Monitor resource usage - ensure all are < 80%
4. Check Pod Restarts/hr - should be 0 in normal operation

### Troubleshooting
1. If components show DOWN in health matrix:
   - Check the error log stream for related failures
   - Review active alerts for specific issues
   
2. For performance issues:
   - Check resource utilization trends
   - Monitor I/O graphs for bottlenecks
   - Review thermal status for throttling

### Trend Analysis
- Use the time range selector to view historical data
- Look for patterns in resource usage
- Identify correlation between alerts and resource spikes

## Alert Thresholds

The dashboard uses color-coded thresholds:

| Metric | Green | Yellow | Orange | Red |
|--------|-------|--------|--------|-----|
| CPU Usage | < 70% | 70-80% | 80-90% | > 90% |
| Memory Usage | < 70% | 70-85% | 85-95% | > 95% |
| Disk Usage | < 70% | 70-85% | 85-95% | > 95% |
| Active Alerts | < 5 | 5-10 | 10-20 | > 20 |
| Pod Restarts | 0 | 1-5 | > 5 | - |

## Refresh Settings

- Default refresh: 30 seconds
- Available options: 10s, 30s, 1m, 5m, 15m, 30m, 1h, 2h, 1d
- Live data streaming for logs panel

## Best Practices

1. **Set as Homepage**: Configure this as your Grafana homepage for quick access
2. **Create Alerts**: Set up Grafana alerts based on the key metrics
3. **Regular Reviews**: Check the dashboard at least twice daily
4. **Document Issues**: When investigating problems, note the time and metrics
5. **Customize**: Adjust thresholds based on your system's normal operating ranges

## Integration with Other Dashboards

This rollup dashboard provides high-level overview. For detailed analysis, drill down to:
- ODIN System Overview: Detailed component metrics
- Claude Code API Monitoring: API usage details
- GPU/Power dashboards: Detailed thermal analysis
- Network Analysis: Connection-level details

## Maintenance

The dashboard auto-discovers services based on Prometheus job labels. No manual updates needed when adding new exporters as long as they follow the standard job naming convention.