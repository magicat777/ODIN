# Claude Token Usage Monitoring

This document explains how to capture and monitor Claude API token usage and costs in your ODIN monitoring stack.

## Overview

The Claude token monitoring system captures token usage from multiple sources:
1. Terminal output when using Claude CLI
2. Shell history with cost information (Ctrl+R)
3. Claude configuration files
4. Active Claude sessions

## Components

### 1. Claude Token Collector (Kubernetes)
- **Service**: `claude-token-collector:9404`
- **Purpose**: Collects token usage from Claude config files and estimates active session usage
- **Metrics**: 
  - `claude_api_tokens_input_total`
  - `claude_api_tokens_output_total`
  - `claude_api_cost_dollars_total`
  - `claude_tokens_per_minute`
  - `claude_cost_per_hour_dollars`

### 2. Claude Token Logger (Local Script)
- **Location**: `/home/magicat777/projects/ODIN/scripts/claude-token-logger.sh`
- **Purpose**: Captures token usage from terminal output
- **Usage**:
  ```bash
  # Log token usage manually
  claude-token-logger.sh log <input_tokens> <output_tokens> <cost> [model]
  
  # Parse a line of output
  claude-token-logger.sh parse "Tokens: 1234 input, 5678 output"
  
  # Show statistics
  claude-token-logger.sh stats
  
  # Export metrics for Prometheus
  claude-token-logger.sh export
  ```

### 3. Claude Wrapper (Shell Integration)
- **Location**: `/home/magicat777/projects/ODIN/scripts/claude-wrapper.sh`
- **Purpose**: Automatically captures token usage when using Claude CLI

## Setup Instructions

### Step 1: Enable Shell Integration

Add to your `.bashrc` or `.zshrc`:
```bash
# Claude token monitoring
source /home/magicat777/projects/ODIN/scripts/claude-wrapper.sh
```

After sourcing, you'll have:
- `claude` command wrapped to capture token usage
- `claude_usage` - Show current token usage statistics
- `claude_metrics` - Export metrics in Prometheus format

### Step 2: Capture Token Usage

#### Automatic Capture
When using the wrapped `claude` command, token usage is automatically captured from output like:
- `Tokens: 1234 input, 5678 output`
- `Usage: $0.05 (1234 tokens)`
- `Cost: $0.075`

#### Manual Capture
For token usage shown in Ctrl+R history or other sources:
```bash
# Example: If you see "$0.075" in your command history
claude-token-logger.sh log 1500 3500 0.075
```

### Step 3: Create a Cron Job (Optional)

To regularly export metrics to a file that can be scraped:
```bash
# Add to crontab
*/5 * * * * /home/magicat777/projects/ODIN/scripts/claude-token-logger.sh export > /var/lib/node_exporter/textfile_collector/claude_tokens.prom
```

## Integration with Terminal

### For tmux Users
The token collector attempts to capture from tmux panes. Ensure tmux is configured to allow pane capture:
```bash
# In tmux.conf
set -g history-limit 50000
```

### For Screen Users
Similar functionality available for GNU Screen users.

### For Regular Terminal
Token usage is captured from:
- Direct output when using Claude CLI
- Shell history (if HISTTIMEFORMAT is set)
- Manual logging

## Viewing Metrics in Grafana

The metrics are available in the **Claude Code API Monitoring** dashboard:
- **Token Usage Trend**: Shows input/output tokens over time
- **API Cost Breakdown**: Pie chart of costs by model
- **API Usage & Cost**: Stat panels showing hourly usage

## Token Pricing Reference

Current Claude API pricing (as of 2024):
- **Claude 3 Opus**: $15/1M input, $75/1M output tokens
- **Claude 3 Sonnet**: $3/1M input, $15/1M output tokens  
- **Claude 3 Haiku**: $0.25/1M input, $1.25/1M output tokens
- **Claude 2.1**: $8/1M input, $24/1M output tokens
- **Claude Instant**: $0.80/1M input, $2.40/1M output tokens

## Troubleshooting

### No Token Data Showing
1. Check if token logger is working:
   ```bash
   claude-token-logger.sh stats
   ```

2. Manually log a test entry:
   ```bash
   claude-token-logger.sh log 100 200 0.01
   ```

3. Check if metrics are being exported:
   ```bash
   claude-token-logger.sh export
   ```

### Token Collector Pod Issues
```bash
# Check pod status
kubectl get pods -n monitoring -l app=claude-token-collector

# Check logs
kubectl logs -n monitoring -l app=claude-token-collector
```

## Advanced Usage

### Custom Token Patterns
Edit `/home/magicat777/projects/ODIN/k8s/claude-token-collector.yaml` to add custom regex patterns for your specific token output format.

### Integration with Other Tools
The token logger can be integrated with:
- IDE extensions that use Claude API
- Custom scripts that call Claude
- CI/CD pipelines

### Webhook Integration
For real-time token tracking, you can modify the logger to send webhooks:
```bash
# In claude-token-logger.sh, add:
webhook_notify() {
    curl -X POST https://your-webhook-url \
         -H "Content-Type: application/json" \
         -d "{\"tokens\":$1,\"cost\":$2}"
}
```

## Best Practices

1. **Regular Monitoring**: Check `claude_usage` daily to track spending
2. **Set Alerts**: Configure Prometheus alerts for high token usage
3. **Project Tracking**: Use different terminal sessions for different projects
4. **Cost Attribution**: Log project names when manually capturing usage

## Future Enhancements

Planned improvements:
1. Browser extension to capture web-based Claude usage
2. Integration with Claude API logs
3. Real-time token usage overlay for terminal
4. Project-based cost allocation
5. Token usage predictions based on patterns