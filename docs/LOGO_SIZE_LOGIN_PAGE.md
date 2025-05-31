# ODIN Logo Size on Login Page - Technical Limitation

## Date: 2025-05-30

### Issue
The ODIN logo size on the login page (http://localhost:31494/login) is constrained by Grafana's built-in CSS, which has hardcoded maximum dimensions.

### Technical Details
1. **Current Logo**: 1440x720 pixels (4x original size)
2. **Display Constraint**: Grafana's login page CSS limits the logo display to approximately 180x90 pixels
3. **CSS Classes**: Dynamically generated (e.g., `css-1q52zsp`) making overrides difficult

### Why It's Limited
- Grafana uses CSS-in-JS with generated class names that change between versions
- The logo is rendered as a background-image with fixed dimensions
- Login page styling is bundled and minified, making runtime modifications complex

### Actual Logo URL
The full-size logo IS available at: http://localhost:31494/public/img/grafana_icon.svg
- This shows the logo at its full 1440x720 resolution
- The limitation is only in how Grafana displays it on the login page

### Workarounds Attempted
1. ✅ ConfigMap with larger SVG (successful - logo is larger)
2. ❌ Custom CSS injection (limited by dynamic class names)
3. ❌ InitContainer modifications (would not persist across pod restarts)

### Alternative Solutions
1. **Custom Login Page**: Replace Grafana's login with a custom HTML page
2. **Grafana Enterprise**: Has more branding customization options
3. **Reverse Proxy**: Inject CSS at the proxy level
4. **Fork Grafana**: Modify source code (not recommended)

### Recommendation
The logo has been successfully increased to 4x size (1440x720). While the login page display is constrained by Grafana's CSS, the logo appears larger throughout the rest of the application (dashboards, side menu). This is a known Grafana limitation that affects all users trying to customize login page branding.

### Where Logo Appears Larger
- Dashboard headers
- Side navigation menu  
- Full-size at: http://localhost:31494/public/img/grafana_icon.svg
- When embedded in dashboards or panels