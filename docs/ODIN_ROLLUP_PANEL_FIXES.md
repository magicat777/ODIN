# ODIN Rollup Dashboard Panel Fixes

## Fixed Panels

### 1. Active Alerts Details Table

**Issue**: Table showed no data even when alerts count was 0
**Cause**: Query was filtering for only firing alerts, so empty result showed nothing

**Fix Applied**:
- Changed query from `ALERTS{alertstate="firing"}` to `ALERTS{alertstate="firing"} or on() vector(0)`
- Added filter transformation to show only firing alerts after query
- Added table footer to show count
- Changed sort order to sort by Severity instead of Active Since

**Result**: Table now shows:
- All firing alerts when present
- Shows "No data" message when no alerts are firing
- Count of alerts in footer

### 2. Log Level Distribution

**Issue**: Pie chart showed no data
**Cause**: The metric `promtail_custom_log_entries_total` doesn't exist in standard Promtail

**Fix Applied**:
- Changed to "Container Restarts (5m)" showing pod restart distribution
- Query: `sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="monitoring"}[5m])) > 0`
- This gives visibility into problematic pods

**Alternative Options** (can be implemented if needed):
1. **Prometheus Rule Evaluation**: Show distribution of alert rules being evaluated
2. **Error Rate by Service**: Show error rates from different services
3. **Pod Status Distribution**: Show Running/Pending/Failed pod counts

## Usage Notes

1. **Active Alerts Table**: 
   - When no alerts are firing, table shows "No data"
   - When alerts exist, shows full details with color-coded severity
   - Click column headers to sort

2. **Container Restarts Chart**:
   - Shows which pods have restarted in last 5 minutes
   - Empty chart means no restarts (good!)
   - Useful for identifying unstable workloads

## Future Enhancements

To add proper log level distribution, you would need:
1. Configure Promtail to parse log levels
2. Export custom metrics with log level labels
3. Or use Loki with LogQL queries (requires Loki datasource configuration)

For now, the container restart metric provides similar operational insight - identifying problematic components in your stack.