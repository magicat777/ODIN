# Network Monitoring TODO - IMPORTANT

## Issue: Network Traffic Analysis Dashboard Missing Process-Level Metrics

The "Network Traffic Analysis" dashboard in Grafana is partially working:
- ✅ System-level network metrics (interface traffic, total RX/TX) are working
- ❌ Process-level network metrics are not showing data

## Root Cause

The network exporter requires specific kernel capabilities and tools to collect per-process network statistics:

1. **`ss -tuanp`** - Requires CAP_NET_ADMIN and proper permissions to show process information
2. **`nethogs`** - Requires root privileges and kernel support for per-process bandwidth monitoring
3. **Process socket mapping** - Needs access to /proc/[pid]/fd/ for all processes

## Current State

The network-exporter pod is running but cannot collect process-level metrics due to:
- Missing kernel capabilities in the container
- Insufficient privileges to read all process information
- `ss` command not showing process details without proper permissions

## Required Fixes

### 1. Update Network Exporter Deployment
Add required capabilities:
```yaml
securityContext:
  privileged: true  # May be needed for full access
  capabilities:
    add:
    - NET_ADMIN
    - NET_RAW
    - SYS_ADMIN
    - SYS_PTRACE  # To read other processes
```

### 2. Consider Alternative Approaches
- Use eBPF-based monitoring (more efficient, less intrusive)
- Deploy a dedicated network monitoring agent (e.g., Cilium Hubble)
- Use systemd socket activation for privileged operations

### 3. Security Considerations
Running with elevated privileges has security implications:
- Consider using a separate namespace
- Implement proper RBAC restrictions
- Use AppArmor/SELinux profiles if available

## Metrics Currently Missing

1. **process_network_receive_bytes_total** - Network bytes received by process
2. **process_network_transmit_bytes_total** - Network bytes transmitted by process
3. **process_network_connections** - Number of connections per process by state
4. **process_network_rx_packets** - Packets received by process
5. **process_network_tx_packets** - Packets transmitted by process

## Dashboard Panels Affected

In "Network Traffic Analysis" dashboard:
- Top Network Consumers (Received)
- Top Network Consumers (Transmitted)
- Network Traffic by Process
- Network Connections by State
- Processes with Most Connections
- Active Connections

## Priority: HIGH

This functionality is important for:
- Identifying network-heavy processes
- Troubleshooting network performance issues
- Security monitoring (unusual network activity)
- Capacity planning

## Next Steps

When ready to implement:
1. Review security policies for the environment
2. Test with elevated privileges in a controlled manner
3. Consider implementing eBPF-based solution for better security
4. Add proper error handling and fallback metrics