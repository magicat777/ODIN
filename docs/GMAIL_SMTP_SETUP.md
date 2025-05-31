# Gmail SMTP Configuration for ODIN Alerts

## Prerequisites

To send emails through Gmail/Google Workspace, you need to create an **App Password** instead of using your regular password.

## Steps to Create Gmail App Password

1. **Enable 2-Factor Authentication** (if not already enabled):
   - Go to https://myaccount.google.com/security
   - Click on "2-Step Verification"
   - Follow the setup process

2. **Generate App Password**:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" from the app dropdown
   - Select "Other" from the device dropdown
   - Enter "ODIN Monitoring" as the name
   - Click "Generate"
   - **Copy the 16-character password** (spaces don't matter)
   dhmw fxpu zhyf oacw

3. **Important**: Save this password securely - you won't be able to see it again!

## Configure ODIN with Gmail

### Option 1: Interactive Setup (Recommended)
```bash
# Run this command and enter your app password when prompted
kubectl create secret generic grafana-smtp-secret \
  --from-literal=smtp-password='YOUR_APP_PASSWORD_HERE' \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Option 2: Manual Setup
1. Edit the secret in `/tmp/grafana-smtp-secret.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-smtp-secret
  namespace: monitoring
type: Opaque
stringData:
  smtp-password: "xxxx xxxx xxxx xxxx"  # Your 16-character app password
```

2. Apply the secret:
```bash
kubectl apply -f /tmp/grafana-smtp-secret.yaml
```

## Gmail SMTP Settings Used

- **SMTP Server**: smtp.gmail.com
- **Port**: 587
- **Security**: STARTTLS (required)
- **Authentication**: Yes
- **Username**: jason.holt@andominia.com
- **Password**: App Password (not your regular password)

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   - Ensure you're using an App Password, not your regular password
   - Check that 2FA is enabled on your Google account
   - Verify the app password was entered correctly (spaces don't matter)

2. **Connection Refused**
   - Gmail might block "less secure apps" - App Passwords bypass this
   - Check firewall rules allow outbound connections to port 587

3. **Emails Not Received**
   - Check spam folder
   - Verify the from address matches your Google account
   - Look in Grafana logs: `kubectl logs -n monitoring deployment/grafana`

### Test Email Configuration

After setup, test the configuration in Grafana:
1. Go to Grafana UI: http://localhost:31494
2. Navigate to Alerting → Contact points
3. Click "Test" on the email contact point
4. Check your inbox

### View Grafana Logs
```bash
# Check for SMTP errors
kubectl logs -n monitoring deployment/grafana | grep -i smtp

# Follow logs in real-time
kubectl logs -n monitoring deployment/grafana -f
```

## Security Notes

- The app password is stored as a Kubernetes Secret (base64 encoded)
- Never commit the actual password to version control
- Rotate app passwords periodically
- You can revoke app passwords at: https://myaccount.google.com/apppasswords

## Alternative: Using OAuth2 (Advanced)

For production environments, consider using OAuth2 instead of SMTP:
- More secure (no password storage)
- Better audit trail
- Can be integrated with Google Workspace policies

This requires additional setup with Google Cloud Platform and is beyond the scope of this guide.
