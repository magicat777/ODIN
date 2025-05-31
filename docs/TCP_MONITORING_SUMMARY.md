# TCP Network Health Monitoring Summary

## Date: 2025-05-30

### ✅ Implementation Complete

1. **TCP Reset Alert Rules**
   - Configured alerts for high TCP reset rates (> 2/sec warning, > 5/sec critical)
   - Alert for high reset percentage (> 20% of connections)
   - Added congestion detection combining resets + retransmissions

2. **Anomaly Detection Integration**
   - Added 4 TCP metrics to ML anomaly detection:
     - `tcp_reset_rate`: Currently showing low anomaly score (3.25%)
     - `tcp_reset_percentage`: Moderate anomaly score (16.4%)
     - `tcp_retransmission_rate`: Low anomaly score (11.5%)
     - `tcp_connection_failures`: No data yet (normal for healthy systems)

3. **Current Status**
   - TCP resets: 0.73/sec (elevated but not critical)
   - Reset percentage: 17.3% of connections (concerning)
   - Retransmissions: 0.074/sec (acceptable)

### 📊 Normal TCP Thresholds

| Metric | Excellent | Good | Warning | Critical |
|--------|-----------|------|---------|----------|
| Reset Rate | < 0.1/s | < 0.5/s | > 2/s | > 5/s |
| Reset % | < 1% | < 5% | > 20% | > 50% |
| Retrans % | < 0.1% | < 0.5% | > 1% | > 5% |

### 🎯 Alert Thresholds Set

1. **HighTCPResetRate**: > 2 resets/sec for 5 minutes
2. **ExcessiveTCPResetRate**: > 5 resets/sec for 2 minutes  
3. **HighTCPResetPercentage**: > 20% of connections reset for 5 minutes
4. **HighTCPRetransmissionRate**: > 1% segments retransmitted for 5 minutes
5. **TCPCongestionDetected**: Combined high resets + retransmissions

### 🔍 Anomaly Detection Features

- **Statistical Analysis**: For reset rate, reset %, and retransmission %
- **Isolation Forest**: For connection failure patterns
- **Dynamic Thresholds**: Automatically adjusted based on 7-day history
- **Time-aware**: Considers hour of day and day of week patterns

### 📈 Next Steps

1. Monitor the alerts over the next 24-48 hours
2. Investigate applications causing high reset rates
3. Check for:
   - Aggressive firewall rules
   - Application timeout settings
   - Keep-alive configurations
   - Network MTU issues

### 🛠️ Troubleshooting High Resets

```bash
# Find top processes with resets
ss -tan state time-wait | awk '{print $4}' | cut -d: -f2 | sort | uniq -c | sort -nr | head

# Check for SYN flood or port scans
netstat -an | grep SYN_RECV | wc -l

# Monitor real-time TCP states
watch -n 1 'ss -s'

# Check application logs for connection errors
journalctl -u <service-name> | grep -i "connection\|reset\|timeout"
```

### 📊 Verification Commands

```bash
# Check current TCP reset rate
curl -s 'http://localhost:31493/api/v1/query?query=rate(node_netstat_Tcp_OutRsts[5m])' | jq '.data.result[0].value[1]'

# Check TCP anomaly scores
curl -s 'http://localhost:31493/api/v1/query?query=anomaly_score{metric_name=~"tcp.*"}' | jq '.data.result[] | {metric: .metric.metric_name, score: .value[1]}'

# Check if any TCP alerts are firing
curl -s http://localhost:31493/api/v1/query?query=ALERTS{alertname=~".*TCP.*"} | jq '.data.result'
```