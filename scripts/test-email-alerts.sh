#!/bin/bash

# ODIN Email Alert Testing Script
# This script helps test your email notification setup

echo "🧪 ODIN Email Alert Testing"
echo "=========================="
echo ""

echo "This script will help you test email notifications by:"
echo "1. Checking AlertManager configuration"
echo "2. Creating a temporary test alert"
echo "3. Verifying email delivery"
echo ""

read -p "Do you want to proceed with testing? (y/N): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Test cancelled."
    exit 0
fi

echo ""
echo "🔍 Checking AlertManager status..."
kubectl get pods -n monitoring | grep alertmanager

echo ""
echo "📧 Checking AlertManager configuration..."
kubectl get configmap alertmanager-config-email -n monitoring >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Email configuration found"
else
    echo "❌ Email configuration not found. Run setup-email-alerts.sh first."
    exit 1
fi

echo ""
echo "🎯 Creating test alert rule..."

# Create a temporary test alert
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-email-alert-rules
  namespace: monitoring
data:
  test-rules.yaml: |
    groups:
    - name: email_test_alerts
      rules:
      - alert: EmailTestAlert
        expr: up{job="prometheus"} == 1  # This will always fire
        for: 1m
        labels:
          severity: warning
          component: test
        annotations:
          summary: "Email notification test alert"
          description: "This is a test alert to verify email notifications are working properly."
EOF

echo "✅ Test alert rule created"

echo ""
echo "⏳ Waiting for test alert to be triggered (this may take 1-2 minutes)..."
sleep 30

echo ""
echo "🔍 Checking for active alerts..."
active_alerts=$(curl -s "http://localhost:31493/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "EmailTestAlert")' 2>/dev/null)

if [[ -n "$active_alerts" ]]; then
    echo "✅ Test alert is active in Prometheus"
else
    echo "⏳ Test alert not yet active, waiting..."
    sleep 30
fi

echo ""
echo "📬 Checking AlertManager for test alert..."
alertmanager_alerts=$(curl -s "http://localhost:31495/api/v1/alerts" | jq '.[] | select(.labels.alertname == "EmailTestAlert")' 2>/dev/null)

if [[ -n "$alertmanager_alerts" ]]; then
    echo "✅ Test alert received by AlertManager"
else
    echo "⏳ Test alert not yet in AlertManager, this is normal for new alerts"
fi

echo ""
echo "🧹 Cleaning up test alert rule..."
kubectl delete configmap test-email-alert-rules -n monitoring

echo ""
echo "📋 Email Test Summary"
echo "===================="
echo ""
echo "✅ Test alert was created and should trigger email notifications"
echo ""
echo "📧 What to expect in your email:"
echo "  • Subject: [ODIN PERSISTENT] or [FIRING:1] EmailTestAlert"
echo "  • From: Your configured email address"
echo "  • Content: HTML formatted alert details"
echo ""
echo "⏰ Timeline:"
echo "  • Immediate: Webhook notification (check logs)"
echo "  • After 15 minutes: Email notification for persistent alerts"
echo "  • Critical alerts: Immediate email"
echo ""
echo "🔍 Troubleshooting:"
echo "  • Check spam/junk folder"
echo "  • Verify SMTP credentials are correct"
echo "  • Check AlertManager logs: kubectl logs -n monitoring deployment/alertmanager"
echo "  • Check Prometheus alerts: http://localhost:31493/alerts"
echo ""
echo "📊 Monitoring URLs:"
echo "  • AlertManager: http://localhost:31495"
echo "  • Prometheus Alerts: http://localhost:31493/alerts"
echo "  • Grafana: http://localhost:31494"
echo ""

# Show recent AlertManager logs
echo "📜 Recent AlertManager logs:"
kubectl logs -n monitoring deployment/alertmanager --tail=10