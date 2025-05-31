#!/bin/bash
# Update admin user avatar to use ODIN logo

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
sleep 10

# Update user preferences to use ODIN logo as avatar
kubectl exec -n monitoring deployment/grafana -- sh -c '
# Copy ODIN logo to user avatar location
cp /usr/share/grafana/public/img/grafana_icon.svg /usr/share/grafana/public/img/user_avatar_admin.svg

# Create a symbolic link for the default user profile image
ln -sf /usr/share/grafana/public/img/grafana_icon.svg /usr/share/grafana/public/img/user_profile.png
'

echo "Admin avatar updated to ODIN logo"