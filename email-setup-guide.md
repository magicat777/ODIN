# ODIN Email Alert Setup Guide

## Current Status
- ✅ Webhook notifications working correctly 
- ✅ Enhanced pod monitoring rules deployed
- ✅ OOM and crash loop detection operational
- ❌ Email configuration needs AlertManager version compatibility fix

## Option 1: Grafana Notification Policies (Recommended)

Grafana has built-in alerting that can send emails directly:

### 1. Access Grafana Alerting
```bash
# Navigate to: http://localhost:31494/alerting/
# Login: admin/admin
```

### 2. Configure Email Contact Point
1. Go to **Alerting > Contact Points**
2. Click **+ Add Contact Point**
3. Configure:
   - **Name**: `email-notifications`
   - **Type**: `Email`
   - **Email addresses**: `jason.holt@andominia.com`
   - **Subject**: `ODIN Alert: {{ .GroupLabels.alertname }}`
   - **Message**: Custom template (see below)

### 3. Create Notification Policy
1. Go to **Alerting > Notification Policies**
2. Create policy for monitoring namespace alerts
3. Route to email contact point

## Option 2: AlertManager SMTP Fix

### Issue Identified
AlertManager v0.28.x has breaking changes in email configuration syntax.

### Solution
```yaml
# Correct v0.28.x syntax (simplified)
receivers:
- name: 'email-receiver'
  email_configs:
  - to: 'jason.holt@andominia.com'
    from: 'odin-alerts@gmail.com'
    smarthost: 'smtp.gmail.com:587'
    auth_username: 'jason.holt@andominia.com'
    auth_password: 'DA!Amar01'
    headers:
      Subject: 'ODIN Alert: {{ .GroupLabels.alertname }}'
```

## Option 3: External Alert Routing

### Webhook to Email Bridge
Current webhook system can be extended with email forwarding:

```python
# Add to webhook-logger
import smtplib
from email.mime.text import MIMEText

def send_email_alert(alert_data):
    msg = MIMEText(format_alert(alert_data))
    msg['Subject'] = f"ODIN Alert: {alert_data['alertname']}"
    msg['From'] = 'odin-alerts@gmail.com'
    msg['To'] = 'jason.holt@andominia.com'
    
    smtp = smtplib.SMTP('smtp.gmail.com', 587)
    smtp.starttls()
    smtp.login('jason.holt@andominia.com', 'DA!Amar01')
    smtp.send_message(msg)
    smtp.quit()
```

## Testing Current System

### Verify Pod Alerts
```bash
# Check enhanced rules are loaded
curl -s http://localhost:31493/api/v1/rules | jq '.data.groups[] | select(.name == "pod-monitoring-enhanced")'

# Check webhook logs for alerts
kubectl logs -n monitoring webhook-logger-7b8c5b74f6-wlhtq --tail=50 | grep -A 10 -B 5 "process-anomaly-detector"
```

### Force Test Alert
```bash
# Create memory pressure to test alerts
kubectl run memory-test --rm -it --image=progrium/stress --restart=Never -- stress --vm 1 --vm-bytes 2G --timeout 30s
```

## Recommended Action

**Immediate**: Use Grafana's built-in email alerting (Option 1)
- Simpler configuration
- No AlertManager version conflicts  
- Rich templating and dashboard integration

**Long-term**: Fix AlertManager SMTP for centralized alerting
- Better for complex routing rules
- Unified notification management
- Supports multiple notification channels