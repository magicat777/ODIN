#!/bin/bash

# Claude wrapper that captures token usage
# Add this to your .bashrc or .zshrc:
# source /home/magicat777/projects/ODIN/scripts/claude-wrapper.sh

CLAUDE_TOKEN_LOGGER="/home/magicat777/projects/ODIN/scripts/claude-token-logger.sh"

# Function to wrap Claude CLI and capture output
claude_with_logging() {
    # Create a temporary file to capture output
    local tmpfile=$(mktemp)
    local exit_code
    
    # Run claude with all arguments, capturing output
    if [ -t 1 ]; then
        # Interactive mode - show output and capture
        claude "$@" 2>&1 | tee "$tmpfile"
        exit_code=${PIPESTATUS[0]}
    else
        # Non-interactive - just capture
        claude "$@" > "$tmpfile" 2>&1
        exit_code=$?
        cat "$tmpfile"
    fi
    
    # Parse output for token usage
    while IFS= read -r line; do
        # Look for token usage patterns
        if [[ "$line" =~ Tokens:|tokens:|Usage:|Cost: ]]; then
            "$CLAUDE_TOKEN_LOGGER" parse "$line" 2>/dev/null
        fi
    done < "$tmpfile"
    
    # Clean up
    rm -f "$tmpfile"
    
    return $exit_code
}

# Create alias
alias claude='claude_with_logging'

# Function to show current token usage
claude_usage() {
    "$CLAUDE_TOKEN_LOGGER" stats
}

# Function to export metrics for Prometheus
claude_metrics() {
    "$CLAUDE_TOKEN_LOGGER" export
}

# Hook into bash command completion to capture costs from Ctrl+R
if [ -n "$BASH_VERSION" ]; then
    # Bash-specific implementation
    claude_capture_from_history() {
        local cmd="$1"
        if [[ "$cmd" =~ \$[0-9]+\.[0-9]+ ]]; then
            # Extract cost from command
            local cost=$(echo "$cmd" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 | tr -d '$')
            if [ -n "$cost" ]; then
                # Estimate tokens from cost (rough approximation)
                local total_tokens=$(echo "scale=0; $cost * 66666" | bc)  # ~$0.015 per 1K tokens
                local input_tokens=$((total_tokens * 20 / 100))
                local output_tokens=$((total_tokens * 80 / 100))
                "$CLAUDE_TOKEN_LOGGER" log "$input_tokens" "$output_tokens" "$cost" 2>/dev/null
            fi
        fi
    }
    
    # Override history expansion if possible
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }claude_capture_from_history \"\$_\""
fi

# For Zsh
if [ -n "$ZSH_VERSION" ]; then
    # Zsh-specific implementation
    preexec() {
        claude_capture_from_history "$1"
    }
fi

echo "Claude token logging enabled. Use 'claude_usage' to see statistics."