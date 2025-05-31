# Grafana Metrics Setup

## Configuration Applied

Grafana metrics collection has been enabled by adding the following to Prometheus configuration:

```yaml
- job_name: 'grafana'
  static_configs:
  - targets: ['grafana:3000']
```

## Available Metrics

Grafana exposes a rich set of metrics at `http://grafana:3000/metrics`. Key metrics include:

### Performance Metrics
- `grafana_http_request_duration_seconds` - HTTP request latencies
- `grafana_database_conn_*` - Database connection pool metrics
- `grafana_api_response_status_total` - API response codes
- `grafana_page_response_status_total` - Page load response codes

### Dashboard & Usage Metrics
- `grafana_api_dashboard_*` - Dashboard API operations
- `grafana_api_user_signup_*` - User signups
- `grafana_api_admin_user_create_total` - Admin user creation
- `grafana_stat_totals_dashboard` - Total dashboards

### Alerting Metrics
- `grafana_alerting_active_alerts` - Currently active alerts
- `grafana_alerting_execution_time_milliseconds` - Alert evaluation time
- `grafana_alerting_request_duration_seconds` - Alert request duration

### System Metrics
- `grafana_build_info` - Grafana version and build info
- `grafana_instance_start_total` - Number of Grafana starts
- `go_memstats_*` - Go runtime memory statistics
- `process_*` - Process level metrics (CPU, memory, file descriptors)

## Using in Dashboards

To use these metrics in your Grafana-metrics dashboard:

1. **API Performance**:
   ```promql
   rate(grafana_http_request_duration_seconds_sum[5m]) / 
   rate(grafana_http_request_duration_seconds_count[5m])
   ```

2. **Request Rate**:
   ```promql
   rate(grafana_http_request_total[5m])
   ```

3. **Error Rate**:
   ```promql
   rate(grafana_api_response_status_total{code=~"5.."}[5m])
   ```

4. **Active Alerts**:
   ```promql
   grafana_alerting_active_alerts
   ```

5. **Memory Usage**:
   ```promql
   go_memstats_heap_inuse_bytes
   ```

6. **Dashboard Count**:
   ```promql
   grafana_stat_totals_dashboard
   ```

## Fixing Your Grafana Dashboard

Your Grafana-metrics dashboard should now show data. Common queries to add:

### Request Latency Heatmap
```promql
grafana_http_request_duration_seconds_bucket
```

### Top API Endpoints by Request Count
```promql
topk(10, sum by (handler) (rate(grafana_api_response_status_total[5m])))
```

### Database Connection Pool
```promql
grafana_database_conn_idle_total
grafana_database_conn_in_use_total
grafana_database_conn_max_open_total
```

### Alert Evaluation Performance
```promql
histogram_quantile(0.95, 
  sum(rate(grafana_alerting_execution_time_milliseconds_bucket[5m])) by (le)
)
```

## Verification

To verify metrics are being collected:

```bash
# Check Prometheus targets
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "grafana")'

# Query a metric
kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=grafana_build_info' | jq '.'
```

## Troubleshooting

If metrics aren't showing:
1. Check Grafana is running: `kubectl get pods -n monitoring | grep grafana`
2. Verify metrics endpoint: `kubectl exec -n monitoring deployment/grafana -- wget -qO- http://localhost:3000/metrics | head`
3. Check Prometheus scraping: Look for errors in Prometheus targets page
4. Ensure firewall/network policies allow port 3000 access between pods