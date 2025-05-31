# ODIN Rollup Dashboard Performance Fixes

## Issues Resolved

1. **Query Timeouts**: Original dashboard was making too many concurrent queries without proper optimization
2. **Missing Datasource**: Hardcoded datasource UIDs were causing connection failures
3. **Complex Queries**: Some queries were too heavy for real-time evaluation

## Optimizations Applied

### 1. Query Optimization
- Changed from `rate()` to `irate()` for instant vectors (more efficient)
- Added `instant: true` to all stat panels (single point queries)
- Added `interval` specifications to prevent over-sampling
- Set `maxDataPoints` limits to reduce query load
- Added `or vector(0)` fallbacks for missing metrics

### 2. Datasource Configuration
- Added datasource variable template
- All panels now use `${datasource}` instead of hardcoded UIDs
- Allows switching between multiple Prometheus instances

### 3. Panel Efficiency
- Removed log panel (most expensive query) - can be added separately if needed
- Simplified network/disk I/O queries with better label filters
- Reduced time series panels to essential metrics only
- Used instant queries for all stat panels

### 4. Time Window Management
- Set appropriate intervals for each query type:
  - Instant queries for current state
  - 2m rate windows for volatile metrics
  - 5m windows for stable metrics
- Limited historical data points in graphs

### 5. Label Filtering
- Added more specific label filters to reduce cardinality:
  - `fstype!="tmpfs"` for disk metrics
  - `device!~"lo|docker.*|veth.*|br.*|cni.*|flannel.*"` for network
  - `device!~"dm-.*"` for disk I/O

## Performance Tips

1. **Adjust Refresh Rate**: If still experiencing timeouts, increase refresh from 30s to 1m
2. **Time Range**: Keep time range to 1h or less for best performance
3. **Browser Cache**: Clear browser cache if dashboard seems stuck
4. **Prometheus Load**: Check Prometheus memory/CPU if queries still timeout

## Verification

After loading the dashboard:
1. All panels should load within 2-3 seconds
2. No spinning indicators after initial load
3. Refresh should complete smoothly
4. Click on any panel - query should execute immediately

## If Issues Persist

1. Check Prometheus performance:
   ```bash
   kubectl top pod -n monitoring | grep prometheus
   ```

2. Verify datasource is selected properly in dashboard

3. Check for any failing queries in Grafana logs:
   ```bash
   kubectl logs -n monitoring deployment/grafana | grep -i error
   ```

4. Consider reducing panel count or splitting into multiple dashboards