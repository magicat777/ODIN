#!/bin/bash

# Claude Token Logger
# This script captures Claude token usage from terminal output and logs it for Prometheus

LOG_DIR="$HOME/.claude/token-logs"
LOG_FILE="$LOG_DIR/token-usage-$(date +%Y%m%d).log"
METRICS_FILE="$LOG_DIR/current-metrics.json"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to capture token usage from terminal output
capture_token_usage() {
    local input_tokens="$1"
    local output_tokens="$2"
    local cost="$3"
    local model="${4:-claude-3-sonnet}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Log to file
    echo "{\"timestamp\":\"$timestamp\",\"model\":\"$model\",\"input_tokens\":$input_tokens,\"output_tokens\":$output_tokens,\"cost\":$cost}" >> "$LOG_FILE"
    
    # Update current metrics
    if [ -f "$METRICS_FILE" ]; then
        current=$(cat "$METRICS_FILE")
        total_input=$(echo "$current" | jq -r '.total_input_tokens // 0')
        total_output=$(echo "$current" | jq -r '.total_output_tokens // 0')
        total_cost=$(echo "$current" | jq -r '.total_cost // 0')
        total_calls=$(echo "$current" | jq -r '.total_calls // 0')
    else
        total_input=0
        total_output=0
        total_cost=0
        total_calls=0
    fi
    
    # Update totals
    total_input=$((total_input + input_tokens))
    total_output=$((total_output + output_tokens))
    total_cost=$(echo "$total_cost + $cost" | bc)
    total_calls=$((total_calls + 1))
    
    # Write updated metrics
    cat > "$METRICS_FILE" <<EOF
{
    "last_updated": "$timestamp",
    "total_input_tokens": $total_input,
    "total_output_tokens": $total_output,
    "total_cost": $total_cost,
    "total_calls": $total_calls,
    "model": "$model"
}
EOF
}

# Function to parse Claude output
parse_claude_output() {
    local line="$1"
    
    # Pattern 1: "Tokens: 1234 input, 5678 output"
    if [[ "$line" =~ Tokens:\ ([0-9]+)\ input,\ ([0-9]+)\ output ]]; then
        input_tokens="${BASH_REMATCH[1]}"
        output_tokens="${BASH_REMATCH[2]}"
        
        # Look for cost on the same or next line
        if [[ "$line" =~ \$([0-9]+\.[0-9]+) ]]; then
            cost="${BASH_REMATCH[1]}"
        else
            # Estimate cost based on Claude 3 Sonnet pricing
            cost=$(echo "scale=4; ($input_tokens * 0.003 + $output_tokens * 0.015) / 1000" | bc)
        fi
        
        capture_token_usage "$input_tokens" "$output_tokens" "$cost"
        return 0
    fi
    
    # Pattern 2: "Usage: $0.05 (1234 tokens)"
    if [[ "$line" =~ Usage:\ \$([0-9]+\.[0-9]+)\ \(([0-9]+)\ tokens\) ]]; then
        cost="${BASH_REMATCH[1]}"
        total_tokens="${BASH_REMATCH[2]}"
        # Estimate input/output split (typically 20/80)
        input_tokens=$((total_tokens * 20 / 100))
        output_tokens=$((total_tokens * 80 / 100))
        
        capture_token_usage "$input_tokens" "$output_tokens" "$cost"
        return 0
    fi
    
    return 1
}

# If called with arguments, parse them
if [ $# -gt 0 ]; then
    case "$1" in
        log)
            # Manual logging: claude-token-logger.sh log <input> <output> <cost> [model]
            shift
            capture_token_usage "$@"
            echo "Logged token usage: $1 input, $2 output, cost: \$$3"
            ;;
        parse)
            # Parse a line of output
            shift
            parse_claude_output "$*"
            ;;
        stats)
            # Show current stats
            if [ -f "$METRICS_FILE" ]; then
                echo "Current Claude Usage Statistics:"
                cat "$METRICS_FILE" | jq .
            else
                echo "No usage statistics found"
            fi
            ;;
        export)
            # Export metrics in Prometheus format
            if [ -f "$METRICS_FILE" ]; then
                metrics=$(cat "$METRICS_FILE")
                echo "# HELP claude_tokens_input_total Total input tokens used"
                echo "# TYPE claude_tokens_input_total counter"
                echo "claude_tokens_input_total{source=\"terminal\"} $(echo "$metrics" | jq -r '.total_input_tokens')"
                echo "# HELP claude_tokens_output_total Total output tokens used"
                echo "# TYPE claude_tokens_output_total counter"
                echo "claude_tokens_output_total{source=\"terminal\"} $(echo "$metrics" | jq -r '.total_output_tokens')"
                echo "# HELP claude_api_cost_dollars_total Total API cost"
                echo "# TYPE claude_api_cost_dollars_total counter"
                echo "claude_api_cost_dollars_total{source=\"terminal\"} $(echo "$metrics" | jq -r '.total_cost')"
                echo "# HELP claude_api_calls_total Total API calls"
                echo "# TYPE claude_api_calls_total counter"
                echo "claude_api_calls_total{source=\"terminal\"} $(echo "$metrics" | jq -r '.total_calls')"
            fi
            ;;
        watch)
            # Watch terminal output for token usage
            echo "Watching for Claude token usage patterns..."
            echo "Press Ctrl+C to stop"
            # This would need to be integrated with your terminal
            ;;
        *)
            echo "Usage: $0 {log|parse|stats|export|watch}"
            echo "  log <input> <output> <cost> [model] - Log token usage"
            echo "  parse <line>                         - Parse a line for token usage"
            echo "  stats                                - Show current statistics"
            echo "  export                               - Export metrics in Prometheus format"
            echo "  watch                                - Watch for token usage (interactive)"
            ;;
    esac
else
    echo "Claude Token Logger"
    echo "Use '$0 stats' to see current usage"
    echo "Use '$0 log <input> <output> <cost>' to manually log usage"
fi