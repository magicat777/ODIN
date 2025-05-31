#!/bin/bash

# ODIN Email Alerts Setup Script
# This script helps configure email notifications for ODIN monitoring alerts

echo "🔔 ODIN Email Alerts Configuration"
echo "=================================="
echo ""

# Check if user wants to proceed
read -p "Do you want to configure email alerts for ODIN monitoring? (y/N): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""
echo "📧 Email Configuration"
echo "====================="

# Get email settings from user
echo "Please provide your email configuration details:"
echo ""

read -p "Your email address (to receive alerts): " user_email
read -p "SMTP server (e.g., smtp.gmail.com:587): " smtp_server
read -p "SMTP username (usually your email): " smtp_username
read -s -p "SMTP password (app password for Gmail): " smtp_password
echo ""

# Validate inputs
if [[ -z "$user_email" || -z "$smtp_server" || -z "$smtp_username" || -z "$smtp_password" ]]; then
    echo "❌ Error: All fields are required!"
    exit 1
fi

echo ""
echo "🔧 Configuring AlertManager..."

# Create base64 encoded password
encoded_password=$(echo -n "$smtp_password" | base64 -w 0)

# Update the AlertManager configuration
sed -i "s/admin@your-domain.com/$user_email/g" /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml
sed -i "s/smtp.gmail.com:587/$smtp_server/g" /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml
sed -i "s/your-email@gmail.com/$smtp_username/g" /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml
sed -i "s/odin-monitoring@your-domain.com/$user_email/g" /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml
sed -i "s/ZGhtdyBmeHB1IHpoeWYgb2Fjdw==/$encoded_password/g" /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml

echo "✅ Configuration file updated!"
echo ""

# Apply the configuration
echo "🚀 Applying email configuration to Kubernetes..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/alertmanager-email-config.yaml

echo ""
echo "⏳ Waiting for AlertManager to restart..."
kubectl rollout restart deployment/alertmanager -n monitoring
kubectl rollout status deployment/alertmanager -n monitoring --timeout=120s

echo ""
echo "✅ Email alerts configuration complete!"
echo ""
echo "📋 Summary:"
echo "  • Email address: $user_email"
echo "  • SMTP server: $smtp_server"
echo "  • Alerts will be sent for:"
echo "    - Critical alerts: Immediately"
echo "    - Persistent alerts: After 15 minutes"
echo "    - Thermal/Power alerts: Within 30 seconds"
echo ""
echo "🧪 Test Email Notification:"
echo "You can test email notifications by temporarily triggering an alert."
echo "Check your email and spam folder for ODIN alert messages."
echo ""
echo "🔗 Access URLs:"
echo "  • AlertManager: http://localhost:31495"
echo "  • Grafana: http://localhost:31494"
echo "  • Prometheus: http://localhost:31493"
echo ""
echo "💡 Tip: For Gmail, make sure you're using an App Password, not your regular password."