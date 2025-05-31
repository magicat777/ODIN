# LogQL Best Practices for ODIN Monitoring

## Overview
This document outlines best practices for writing LogQL queries in the ODIN monitoring system to avoid common syntax errors and ensure optimal performance.

## Fixed Issues

### ❌ Problem: Perl-style Regex Not Supported
**Broken Query:**
```logql
{namespace="monitoring"} |~ "(?i)error|warn|fail|critical|exception" |~ "^((?!Failed to update stats for container|binary.Read: invalid type int32).)*$"
```

**Error:** `parse error : error parsing regexp: invalid or unsupported Perl syntax: (?!`

### ✅ Solution: Use RE2-Compatible Negative Matching
**Fixed Query:**
```logql
{namespace="monitoring"} |~ "(?i)error|warn|fail|critical|exception" !~ "Failed to update stats for container" !~ "binary.Read: invalid type int32"
```

## LogQL Syntax Reference

### Supported Regex Features (RE2)
- ✅ `(?i)` - Case insensitive matching
- ✅ `|` - OR operator  
- ✅ `.*` - Match any character
- ✅ `^` and `$` - Line anchors
- ✅ `[]` - Character classes
- ✅ `+`, `*`, `?` - Quantifiers

### NOT Supported (Perl-style)
- ❌ `(?!)` - Negative lookahead
- ❌ `(?<!.)` - Negative lookbehind
- ❌ `(?=.)` - Positive lookahead
- ❌ `(?<=.)` - Positive lookbehind

### Recommended Patterns

#### 1. Filter Error Logs (Exclude Known Issues)
```logql
# Good: Use multiple !~ operators
{namespace="monitoring"} |~ "(?i)error|exception|fatal" !~ "Failed to update stats" !~ "binary.Read"

# Bad: Perl-style negative lookahead
{namespace="monitoring"} |~ "error" |~ "^((?!Failed to update).)*$"
```

#### 2. Case-Insensitive Matching
```logql
# Good: Use (?i) flag
{job="app"} |~ "(?i)error|warn|fail"

# Alternative: Multiple patterns
{job="app"} |~ "error|Error|ERROR|warn|Warn|WARN"
```

#### 3. Complex Filtering
```logql
# Good: Chain multiple filters
{namespace="monitoring"} 
|~ "(?i)error|exception" 
!~ "connection refused" 
!~ "timeout" 
| line_format "{{.timestamp}} {{.level}} {{.message}}"
```

#### 4. Performance Optimization
```logql
# Good: Most specific labels first
{namespace="monitoring",pod="prometheus-123"} |~ "error"

# Less optimal: Broad label selection
{pod=~".*"} |~ "error" | json | namespace="monitoring"
```

## Common LogQL Patterns for ODIN

### Monitor All Errors (Clean)
```logql
{namespace="monitoring"} 
|~ "(?i)error|exception|fatal|critical" 
!~ "Failed to update stats for container" 
!~ "binary.Read: invalid type int32"
!~ "level=info"
```

### Service-Specific Logs
```logql
# Prometheus errors only
{namespace="monitoring",pod=~"prometheus-.*"} |~ "(?i)error|fail"

# Grafana warnings and errors  
{namespace="monitoring",pod=~"grafana-.*"} |~ "(?i)warn|error"

# GPU monitoring issues
{namespace="monitoring",pod=~".*exporter.*"} |~ "(?i)gpu|nvidia|temperature|thermal"
```

### Time-Based Filtering
```logql
# Last hour errors
{namespace="monitoring"} |~ "error" [1h]

# Rate of errors per minute
rate({namespace="monitoring"} |~ "error" [1m])

# Count errors by service
count by (pod) (
  {namespace="monitoring"} |~ "(?i)error|exception" !~ "non-critical"
)
```

### JSON Log Parsing
```logql
# Parse JSON logs and filter by level
{namespace="monitoring"} 
| json 
| level="error" 
| line_format "{{.timestamp}} [{{.level}}] {{.message}}"
```

## Performance Tips

### 1. Use Specific Label Selectors
```logql
# Good: Narrow scope first
{namespace="monitoring",job="prometheus"} |~ "error"

# Slower: Broad scope with filtering
{job=~".*"} |~ "error" | namespace="monitoring"
```

### 2. Limit Time Ranges
```logql
# Good: Reasonable time window
{namespace="monitoring"} |~ "error" [15m]

# Avoid: Very large time windows without limits
{namespace="monitoring"} |~ "error" [7d]
```

### 3. Use Line Limits
```logql
# Good: Limit results for dashboards
{namespace="monitoring"} |~ "error" | head 100

# For alerts: Focus on recent logs
{namespace="monitoring"} |~ "critical" [5m]
```

## Dashboard Query Examples

### Error Summary Panel
```logql
# Query A: Error count by service
count by (pod) (
  {namespace="monitoring"} |~ "(?i)error|exception|fatal" 
  !~ "Failed to update stats" 
  [5m]
)
```

### Real-time Error Stream
```logql
# Query B: Live error logs (filtered)
{namespace="monitoring"} 
|~ "(?i)error|exception|critical" 
!~ "Failed to update stats for container"
!~ "binary.Read: invalid type int32"
!~ "connection refused"
```

### Service Health Check
```logql
# Query C: Service restart indicators
{namespace="monitoring"} |~ "(?i)started|stopped|restarted|shutdown"
```

## Troubleshooting Common Errors

### 1. `parse error: invalid or unsupported Perl syntax`
- **Cause**: Using `(?!` or `(?=` patterns
- **Fix**: Use `!~` for negative matching instead

### 2. `parse error: trailing backslash at end of expression`
- **Cause**: Unescaped backslashes in regex
- **Fix**: Double-escape backslashes: `\\` or use raw strings

### 3. `context deadline exceeded`
- **Cause**: Query too complex or time range too large
- **Fix**: Narrow time range, add more specific labels, use `| head N`

### 4. `no data`
- **Cause**: Labels don't match or regex too restrictive  
- **Fix**: Test with simpler query first, verify label values

## ODIN-Specific Exclusions

These patterns are commonly excluded in ODIN dashboards as they're non-critical:

```logql
# Common exclusions for cleaner logs
!~ "Failed to update stats for container"          # cAdvisor cgroups v2 compatibility
!~ "binary.Read: invalid type int32"               # cAdvisor non-critical errors  
!~ "connection refused.*webhook"                   # Expected webhook failures
!~ "level=info.*probe"                            # Health check noise
!~ "context deadline exceeded.*scrape"            # Temporary scrape timeouts
```

## Testing LogQL Queries

Before adding to dashboards, test queries using:

1. **Grafana Explore**: Test syntax and performance
2. **Loki API**: Direct API testing
3. **Small time windows**: Start with [5m] then expand
4. **Label validation**: Verify labels exist with `{namespace="monitoring"}`

## Resources

- [LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)
- [RE2 Syntax Reference](https://github.com/google/re2/wiki/Syntax)
- [Loki Best Practices](https://grafana.com/docs/loki/latest/best-practices/)