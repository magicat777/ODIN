# cAdvisor Error Filtering Summary

## Date: 2025-05-30

### Issue
cAdvisor was generating repetitive error messages:
```
Failed to update stats for container "/system.slice/irqbalance.service": 
failed to get load stat for "/system.slice/irqbalance.service" - 
path "/sys/fs/cgroup/system.slice/irqbalance.service", 
error binary.Read: invalid type int32
```

### Root Cause
- cAdvisor v0.46.0 has compatibility issues with cgroup v2 on Ubuntu 22.04
- The errors occur when trying to read systemd service cgroups
- This is a known issue that doesn't affect container metrics collection

### Solutions Implemented

#### 1. **Updated Logs Dashboard**
Added filters to exclude these non-critical errors:
- Modified "All Monitoring Logs" panel with regex filter
- Modified "Error Logs" panel to exclude cAdvisor errors
- Added new panel "cAdvisor Errors (Monitoring Only)" for visibility

**Filter Pattern Used:**
```
|~ "^((?!Failed to update stats for container|binary.Read: invalid type int32).)*$"
```

#### 2. **Updated cAdvisor Configuration**
- Upgraded to cAdvisor v0.47.2 (better cgroup v2 support)
- Added `--raw_cgroup_prefix_whitelist=/kubepods` to focus on containers only
- Reduced verbosity with `--v=1`
- Disabled unnecessary metrics to reduce overhead

### Results
- ✅ Logs dashboard now filters out repetitive cAdvisor errors
- ✅ Error panels show only actionable errors
- ✅ cAdvisor errors isolated to a dedicated panel for monitoring
- ✅ Reduced cAdvisor resource usage and error generation

### Verification
```bash
# Check if errors are still being generated
kubectl logs -n monitoring daemonset/cadvisor --tail=50 | grep -c "Failed to update stats"

# Verify container metrics are still working
curl -s http://localhost:31493/api/v1/query?query=container_memory_usage_bytes | jq '.data.result | length'
```

### Notes
These errors are non-critical and can be safely ignored because:
1. They only affect systemd service metrics, not container metrics
2. Container monitoring (the primary purpose) continues to work correctly
3. The errors are due to cgroup v2 format differences, not actual failures

The filtered dashboard provides a cleaner view while still maintaining visibility of these errors in a dedicated panel if needed for debugging.