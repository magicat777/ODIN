#!/bin/bash

# ODIN Health Check and Recovery Script
# Run after reboot to ensure all services are operational

set -euo pipefail

NAMESPACE="monitoring"
LOG_FILE="$HOME/odin-health-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_k3s() {
    log "Checking K3s cluster status..."
    if ! kubectl get nodes &>/dev/null; then
        log "ERROR: K3s cluster not accessible"
        return 1
    fi
    log "✓ K3s cluster is accessible"
}

wait_for_namespace() {
    log "Waiting for monitoring namespace..."
    local count=0
    while ! kubectl get namespace "$NAMESPACE" &>/dev/null && [ $count -lt 30 ]; do
        sleep 2
        ((count++))
    done
    
    if [ $count -eq 30 ]; then
        log "ERROR: Monitoring namespace not found"
        return 1
    fi
    log "✓ Monitoring namespace exists"
}

check_and_restart_deployment() {
    local deployment=$1
    log "Checking deployment: $deployment"
    
    local ready=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [ "$ready" != "$desired" ]; then
        log "RESTARTING: $deployment ($ready/$desired ready)"
        kubectl rollout restart deployment/"$deployment" -n "$NAMESPACE"
        kubectl rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout=120s
        log "✓ $deployment restarted successfully"
    else
        log "✓ $deployment is healthy ($ready/$desired ready)"
    fi
}

check_and_restart_daemonset() {
    local daemonset=$1
    log "Checking daemonset: $daemonset"
    
    local ready=$(kubectl get daemonset "$daemonset" -n "$NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    local desired=$(kubectl get daemonset "$daemonset" -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "1")
    
    if [ "$ready" != "$desired" ]; then
        log "RESTARTING: $daemonset ($ready/$desired ready)"
        kubectl rollout restart daemonset/"$daemonset" -n "$NAMESPACE"
        kubectl rollout status daemonset/"$daemonset" -n "$NAMESPACE" --timeout=120s
        log "✓ $daemonset restarted successfully"
    else
        log "✓ $daemonset is healthy ($ready/$desired ready)"
    fi
}

main() {
    log "=== ODIN Health Check Started ==="
    
    # Check K3s cluster
    if ! check_k3s; then
        log "FATAL: Cannot proceed without K3s cluster"
        exit 1
    fi
    
    # Wait for namespace
    if ! wait_for_namespace; then
        log "FATAL: Monitoring namespace not available"
        exit 1
    fi
    
    # Core monitoring stack
    log "Checking core monitoring stack..."
    check_and_restart_deployment "prometheus"
    check_and_restart_deployment "grafana"
    check_and_restart_deployment "alertmanager"
    check_and_restart_deployment "loki"
    
    # Exporters and collectors
    log "Checking exporters and collectors..."
    check_and_restart_daemonset "node-exporter"
    check_and_restart_daemonset "promtail"
    check_and_restart_daemonset "power-exporter"
    check_and_restart_daemonset "process-exporter"
    check_and_restart_daemonset "razer-exporter"
    check_and_restart_daemonset "claude-code-exporter"
    check_and_restart_deployment "claude-token-collector"
    check_and_restart_deployment "kube-state-metrics"
    check_and_restart_deployment "webhook-logger"
    
    log "=== ODIN Health Check Completed ==="
    log "All services verified. Check Grafana at http://odin.local:31494"
}

main "$@"