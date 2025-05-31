# Proof of Concept: ODIN Docker Compose with Environment Profiles

## Overview

This POC demonstrates a lightweight ODIN deployment using Docker Compose with profile-based configurations, suitable for non-Kubernetes environments.

## Directory Structure

```
odin-standalone/
├── docker-compose.yml          # Base services
├── docker-compose.override.yml # Local overrides
├── profiles/
│   ├── .env.base              # Base configuration
│   ├── .env.storage           # Storage monitoring profile
│   ├── .env.homelab           # Home lab profile
│   ├── .env.enterprise        # Enterprise profile
│   └── .env.gaming            # Gaming rig profile
├── configs/
│   ├── prometheus/
│   │   ├── prometheus.base.yml
│   │   └── rules/
│   ├── grafana/
│   │   ├── provisioning/
│   │   └── dashboards/
│   └── exporters/
│       ├── node/
│       ├── storage/
│       └── custom/
├── scripts/
│   ├── odin-deploy.sh         # Main deployment script
│   ├── detect-hardware.sh     # Auto-detection
│   ├── generate-dashboards.py # Dashboard generator
│   └── backup-restore.sh      # Backup utilities
├── templates/
│   ├── dashboard.j2           # Dashboard templates
│   └── prometheus-config.j2   # Config templates
└── data/                      # Persistent data
    ├── prometheus/
    ├── grafana/
    └── loki/
```

## Core Files

### docker-compose.yml
```yaml
version: '3.8'

x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

services:
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION:-v2.45.0}
    container_name: odin-prometheus
    restart: unless-stopped
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    volumes:
      - ./configs/prometheus:/etc/prometheus
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-30d}'
      - '--web.enable-lifecycle'
    networks:
      - odin-net
    logging: *default-logging
    profiles: ["base", "storage", "homelab", "enterprise", "gaming"]

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION:-10.0.0}
    container_name: odin-grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT:-3000}:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_INSTALL_PLUGINS=${GRAFANA_PLUGINS:-}
    volumes:
      - ./configs/grafana/provisioning:/etc/grafana/provisioning
      - ./configs/grafana/dashboards:/var/lib/grafana/dashboards
      - ./data/grafana:/var/lib/grafana
    networks:
      - odin-net
    logging: *default-logging
    profiles: ["base", "storage", "homelab", "enterprise", "gaming"]

  loki:
    image: grafana/loki:${LOKI_VERSION:-2.9.0}
    container_name: odin-loki
    restart: unless-stopped
    ports:
      - "${LOKI_PORT:-3100}:3100"
    volumes:
      - ./configs/loki:/etc/loki
      - ./data/loki:/loki
    command: -config.file=/etc/loki/loki.yml
    networks:
      - odin-net
    logging: *default-logging
    profiles: ["base", "storage", "homelab", "enterprise", "gaming"]

  # Node Exporter - Base Profile
  node-exporter:
    image: prom/node-exporter:${NODE_EXPORTER_VERSION:-v1.6.0}
    container_name: odin-node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    profiles: ["base", "storage", "homelab", "enterprise", "gaming"]

  # Storage Exporter - Storage Profile
  snmp-exporter:
    image: prom/snmp-exporter:${SNMP_EXPORTER_VERSION:-v0.24.1}
    container_name: odin-snmp-exporter
    restart: unless-stopped
    ports:
      - "${SNMP_EXPORTER_PORT:-9116}:9116"
    volumes:
      - ./configs/exporters/storage/snmp.yml:/etc/snmp_exporter/snmp.yml
    networks:
      - odin-net
    profiles: ["storage", "enterprise"]

  # Custom Storage Exporter
  isilon-exporter:
    build:
      context: ./exporters/isilon
      dockerfile: Dockerfile
    container_name: odin-isilon-exporter
    restart: unless-stopped
    environment:
      - ISILON_HOST=${ISILON_HOST}
      - ISILON_USER=${ISILON_USER}
      - ISILON_PASS=${ISILON_PASS}
    ports:
      - "${ISILON_EXPORTER_PORT:-9117}:9117"
    networks:
      - odin-net
    profiles: ["storage"]

  # NVIDIA GPU Exporter - Gaming Profile
  nvidia-exporter:
    image: nvidia/dcgm-exporter:${DCGM_VERSION:-3.0.0-1-ubuntu20.04}
    container_name: odin-nvidia-exporter
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    ports:
      - "${NVIDIA_EXPORTER_PORT:-9400}:9400"
    networks:
      - odin-net
    profiles: ["gaming", "enterprise"]

  # Razer Exporter - Gaming Profile
  razer-exporter:
    build:
      context: ./exporters/razer
      dockerfile: Dockerfile
    container_name: odin-razer-exporter
    restart: unless-stopped
    privileged: true
    volumes:
      - /dev:/dev
      - /sys:/sys
    ports:
      - "${RAZER_EXPORTER_PORT:-9401}:9401"
    networks:
      - odin-net
    profiles: ["gaming"]

  # Alert Manager
  alertmanager:
    image: prom/alertmanager:${ALERTMANAGER_VERSION:-v0.26.0}
    container_name: odin-alertmanager
    restart: unless-stopped
    ports:
      - "${ALERTMANAGER_PORT:-9093}:9093"
    volumes:
      - ./configs/alertmanager:/etc/alertmanager
      - ./data/alertmanager:/alertmanager
    networks:
      - odin-net
    profiles: ["base", "storage", "homelab", "enterprise", "gaming"]

networks:
  odin-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### Profile Configurations

#### profiles/.env.base
```bash
# Base Profile - Minimal monitoring setup
PROFILE_NAME=base
COMPOSE_PROFILES=base

# Versions
PROMETHEUS_VERSION=v2.45.0
GRAFANA_VERSION=10.0.0
NODE_EXPORTER_VERSION=v1.6.0
LOKI_VERSION=2.9.0

# Ports
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
LOKI_PORT=3100

# Prometheus Config
PROMETHEUS_RETENTION=30d
PROMETHEUS_SCRAPE_INTERVAL=30s

# Grafana Config
GRAFANA_PASSWORD=changeme
GRAFANA_PLUGINS=

# Features
ENABLE_ALERTING=true
ENABLE_LOGGING=true
```

#### profiles/.env.storage
```bash
# Storage Profile - Optimized for storage monitoring
PROFILE_NAME=storage
COMPOSE_PROFILES=base,storage

# Inherit base settings
source .env.base

# Override retention for longer storage
PROMETHEUS_RETENTION=90d
PROMETHEUS_SCRAPE_INTERVAL=15s

# Storage-specific exporters
SNMP_EXPORTER_VERSION=v0.24.1
SNMP_EXPORTER_PORT=9116

# Isilon Configuration
ISILON_HOST=${ISILON_HOST:-isilon.local}
ISILON_USER=${ISILON_USER:-monitor}
ISILON_PASS=${ISILON_PASS:-}
ISILON_EXPORTER_PORT=9117

# Additional Grafana plugins
GRAFANA_PLUGINS=grafana-piechart-panel,snuids-trafficlights-panel

# Storage-specific dashboards
DASHBOARDS_ENABLED="storage-overview,isilon-performance,capacity-planning,iops-latency"
```

#### profiles/.env.gaming
```bash
# Gaming Profile - For gaming rigs with GPU monitoring
PROFILE_NAME=gaming
COMPOSE_PROFILES=base,gaming

# Inherit base settings
source .env.base

# Gaming-specific settings
PROMETHEUS_RETENTION=7d
PROMETHEUS_SCRAPE_INTERVAL=10s

# NVIDIA Configuration
NVIDIA_VISIBLE_DEVICES=all
DCGM_VERSION=3.0.0-1-ubuntu20.04
NVIDIA_EXPORTER_PORT=9400

# Razer Configuration
RAZER_EXPORTER_PORT=9401
RAZER_DEVICE_PATH=/dev/hidraw*

# Gaming dashboards
DASHBOARDS_ENABLED="gpu-overview,thermal-management,power-consumption,gaming-performance"

# High-frequency metrics for gaming
GAMING_METRICS_INTERVAL=5s
```

### Deployment Script

#### scripts/odin-deploy.sh
```bash
#!/bin/bash
set -e

# ODIN Deployment Script
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
PROFILE="base"
AUTO_DETECT=false
BACKUP_EXISTING=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --auto-detect)
            AUTO_DETECT=true
            shift
            ;;
        --no-backup)
            BACKUP_EXISTING=false
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

show_help() {
    cat << EOF
ODIN Deployment Script v${VERSION}

Usage: ./odin-deploy.sh [OPTIONS]

Options:
    --profile <name>     Use specific profile (base, storage, homelab, gaming)
    --auto-detect        Auto-detect hardware and suggest profile
    --no-backup          Skip backup of existing data
    --help               Show this help message

Examples:
    # Deploy with auto-detection
    ./odin-deploy.sh --auto-detect

    # Deploy storage monitoring profile
    ./odin-deploy.sh --profile storage

    # Deploy without backing up existing data
    ./odin-deploy.sh --profile gaming --no-backup
EOF
}

# Auto-detection function
detect_profile() {
    echo -e "${YELLOW}Running hardware detection...${NC}"
    
    local suggested_profile="base"
    local detected_features=()
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        detected_features+=("NVIDIA GPU")
        suggested_profile="gaming"
    fi
    
    # Check for storage systems
    if ping -c1 -W1 ${ISILON_HOST:-isilon.local} &> /dev/null 2>&1; then
        detected_features+=("Isilon Storage")
        suggested_profile="storage"
    fi
    
    # Check for Razer hardware
    if lsusb | grep -i razer &> /dev/null; then
        detected_features+=("Razer Hardware")
        suggested_profile="gaming"
    fi
    
    # Check system resources
    total_memory=$(free -g | awk '/^Mem:/{print $2}')
    cpu_count=$(nproc)
    
    if [[ $total_memory -gt 32 ]] && [[ $cpu_count -gt 8 ]]; then
        detected_features+=("High-end System (${total_memory}GB RAM, ${cpu_count} CPUs)")
        if [[ "$suggested_profile" == "base" ]]; then
            suggested_profile="homelab"
        fi
    fi
    
    echo -e "${GREEN}Detected features:${NC}"
    for feature in "${detected_features[@]}"; do
        echo "  - $feature"
    done
    
    echo -e "${GREEN}Suggested profile: ${suggested_profile}${NC}"
    
    if [[ "$AUTO_DETECT" == true ]]; then
        PROFILE=$suggested_profile
    else
        read -p "Use suggested profile? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            PROFILE=$suggested_profile
        fi
    fi
}

# Backup function
backup_data() {
    if [[ "$BACKUP_EXISTING" == true ]] && [[ -d "$PROJECT_ROOT/data" ]]; then
        echo -e "${YELLOW}Backing up existing data...${NC}"
        backup_dir="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "$PROJECT_ROOT/data" "$backup_dir/"
        echo -e "${GREEN}Backup created at: $backup_dir${NC}"
    fi
}

# Generate configuration
generate_config() {
    echo -e "${YELLOW}Generating configuration for profile: $PROFILE${NC}"
    
    # Copy profile environment
    cp "$PROJECT_ROOT/profiles/.env.$PROFILE" "$PROJECT_ROOT/.env"
    
    # Generate Prometheus configuration
    python3 "$SCRIPT_DIR/generate-config.py" \
        --profile "$PROFILE" \
        --output "$PROJECT_ROOT/configs/prometheus/prometheus.yml"
    
    # Generate dashboards
    python3 "$SCRIPT_DIR/generate-dashboards.py" \
        --profile "$PROFILE" \
        --output-dir "$PROJECT_ROOT/configs/grafana/dashboards"
}

# Deploy function
deploy() {
    echo -e "${YELLOW}Deploying ODIN with profile: $PROFILE${NC}"
    
    # Create necessary directories
    mkdir -p "$PROJECT_ROOT"/{data,configs,logs}
    mkdir -p "$PROJECT_ROOT"/data/{prometheus,grafana,loki,alertmanager}
    
    # Set proper permissions
    chmod -R 777 "$PROJECT_ROOT"/data/grafana
    
    # Load environment
    source "$PROJECT_ROOT/.env"
    
    # Pull images
    docker-compose --profile "$COMPOSE_PROFILES" pull
    
    # Start services
    docker-compose --profile "$COMPOSE_PROFILES" up -d
    
    # Wait for services
    echo -e "${YELLOW}Waiting for services to start...${NC}"
    sleep 10
    
    # Check health
    check_health
}

# Health check function
check_health() {
    echo -e "${YELLOW}Checking service health...${NC}"
    
    services=("prometheus:9090" "grafana:3000" "loki:3100")
    
    for service in "${services[@]}"; do
        name="${service%:*}"
        port="${service#*:}"
        
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" | grep -q "200\|302"; then
            echo -e "  ${GREEN}✓${NC} $name is healthy"
        else
            echo -e "  ${RED}✗${NC} $name is not responding"
        fi
    done
}

# Main execution
main() {
    echo -e "${GREEN}ODIN Deployment Script v${VERSION}${NC}"
    echo "================================"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run detection if requested
    if [[ "$AUTO_DETECT" == true ]] || [[ "$PROFILE" == "base" ]]; then
        detect_profile
    fi
    
    # Confirm deployment
    echo -e "\n${YELLOW}Deployment Summary:${NC}"
    echo "  Profile: $PROFILE"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  Backup: $BACKUP_EXISTING"
    
    read -p "Continue with deployment? [Y/n] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    # Execute deployment steps
    backup_data
    generate_config
    deploy
    
    echo -e "\n${GREEN}Deployment complete!${NC}"
    echo "Access Grafana at: http://localhost:3000"
    echo "Default credentials: admin / $(grep GRAFANA_PASSWORD .env | cut -d= -f2)"
}

# Run main function
main
```

### Dashboard Generator

#### scripts/generate-dashboards.py
```python
#!/usr/bin/env python3
"""
ODIN Dashboard Generator
Generates Grafana dashboards based on selected profile
"""

import json
import os
import argparse
from jinja2 import Template
import yaml

# Dashboard templates
DASHBOARD_TEMPLATES = {
    'storage': {
        'isilon-overview': {
            'title': 'Isilon Storage Overview',
            'panels': [
                {
                    'title': 'Cluster Health',
                    'type': 'stat',
                    'targets': [
                        {'expr': 'isilon_cluster_health'}
                    ]
                },
                {
                    'title': 'Storage Capacity',
                    'type': 'gauge',
                    'targets': [
                        {'expr': '(1 - (isilon_capacity_free / isilon_capacity_total)) * 100'}
                    ]
                },
                {
                    'title': 'IOPS by Node',
                    'type': 'graph',
                    'targets': [
                        {'expr': 'rate(isilon_node_iops[5m])'}
                    ]
                }
            ]
        }
    },
    'gaming': {
        'gpu-overview': {
            'title': 'GPU Performance Overview',
            'panels': [
                {
                    'title': 'GPU Temperature',
                    'type': 'gauge',
                    'targets': [
                        {'expr': 'nvidia_gpu_temperature_celsius'}
                    ],
                    'thresholds': [
                        {'value': 60, 'color': 'green'},
                        {'value': 75, 'color': 'yellow'},
                        {'value': 85, 'color': 'red'}
                    ]
                },
                {
                    'title': 'GPU Utilization',
                    'type': 'graph',
                    'targets': [
                        {'expr': 'nvidia_gpu_utilization_percent'}
                    ]
                },
                {
                    'title': 'Power Draw',
                    'type': 'stat',
                    'targets': [
                        {'expr': 'nvidia_gpu_power_draw_watts'}
                    ]
                }
            ]
        }
    }
}

def generate_dashboard(template, profile_config):
    """Generate a complete Grafana dashboard from template"""
    
    dashboard = {
        'version': 1,
        'uid': template.get('uid', template['title'].lower().replace(' ', '-')),
        'title': template['title'],
        'tags': ['odin', profile_config['name']],
        'timezone': 'browser',
        'schemaVersion': 30,
        'panels': []
    }
    
    # Generate panels
    for idx, panel_template in enumerate(template['panels']):
        panel = {
            'id': idx + 1,
            'title': panel_template['title'],
            'type': panel_template.get('type', 'graph'),
            'gridPos': {
                'x': (idx % 2) * 12,
                'y': (idx // 2) * 8,
                'w': 12,
                'h': 8
            },
            'targets': []
        }
        
        # Add targets
        for target in panel_template['targets']:
            panel['targets'].append({
                'expr': target['expr'],
                'refId': chr(65 + len(panel['targets'])),
                'datasource': 'Prometheus'
            })
        
        # Add thresholds if specified
        if 'thresholds' in panel_template:
            panel['thresholds'] = panel_template['thresholds']
        
        dashboard['panels'].append(panel)
    
    return dashboard

def main():
    parser = argparse.ArgumentParser(description='Generate ODIN dashboards')
    parser.add_argument('--profile', required=True, help='Profile name')
    parser.add_argument('--output-dir', required=True, help='Output directory')
    args = parser.parse_args()
    
    # Load profile configuration
    profile_config = {
        'name': args.profile,
        'dashboards': DASHBOARD_TEMPLATES.get(args.profile, {})
    }
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Generate dashboards
    for dashboard_name, template in profile_config['dashboards'].items():
        dashboard = generate_dashboard(template, profile_config)
        
        output_file = os.path.join(args.output_dir, f'{dashboard_name}.json')
        with open(output_file, 'w') as f:
            json.dump(dashboard, f, indent=2)
        
        print(f'Generated dashboard: {output_file}')

if __name__ == '__main__':
    main()
```

### Custom Exporters

#### exporters/isilon/Dockerfile
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY isilon_exporter.py .

EXPOSE 9117

CMD ["python", "isilon_exporter.py"]
```

#### exporters/isilon/isilon_exporter.py
```python
#!/usr/bin/env python3
"""
Isilon Storage Exporter for Prometheus
"""

import os
import time
import requests
from prometheus_client import start_http_server, Gauge, Counter
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
ISILON_HOST = os.environ.get('ISILON_HOST', 'isilon.local')
ISILON_USER = os.environ.get('ISILON_USER', 'monitor')
ISILON_PASS = os.environ.get('ISILON_PASS', '')
ISILON_PORT = os.environ.get('ISILON_PORT', '8080')
METRICS_PORT = int(os.environ.get('METRICS_PORT', '9117'))

# Metrics
cluster_health = Gauge('isilon_cluster_health', 'Cluster health status')
capacity_total = Gauge('isilon_capacity_total_bytes', 'Total capacity in bytes')
capacity_used = Gauge('isilon_capacity_used_bytes', 'Used capacity in bytes')
capacity_free = Gauge('isilon_capacity_free_bytes', 'Free capacity in bytes')
node_count = Gauge('isilon_node_count', 'Number of nodes in cluster')
node_status = Gauge('isilon_node_status', 'Node status', ['node_id', 'node_name'])
iops_total = Gauge('isilon_iops_total', 'Total IOPS')
throughput_read = Gauge('isilon_throughput_read_bytes', 'Read throughput in bytes/sec')
throughput_write = Gauge('isilon_throughput_write_bytes', 'Write throughput in bytes/sec')

class IsilonCollector:
    def __init__(self):
        self.base_url = f"https://{ISILON_HOST}:{ISILON_PORT}/platform"
        self.session = requests.Session()
        self.session.auth = (ISILON_USER, ISILON_PASS)
        self.session.verify = False  # For self-signed certificates
    
    def collect_metrics(self):
        """Collect all metrics from Isilon"""
        try:
            # Get cluster status
            self._collect_cluster_status()
            
            # Get capacity information
            self._collect_capacity()
            
            # Get performance metrics
            self._collect_performance()
            
        except Exception as e:
            logger.error(f"Error collecting metrics: {e}")
    
    def _collect_cluster_status(self):
        """Collect cluster status metrics"""
        response = self.session.get(f"{self.base_url}/1/cluster/config")
        if response.status_code == 200:
            data = response.json()
            cluster_health.set(1 if data.get('is_healthy', False) else 0)
    
    def _collect_capacity(self):
        """Collect capacity metrics"""
        response = self.session.get(f"{self.base_url}/1/statistics/current?key=cluster.capacity.*")
        if response.status_code == 200:
            data = response.json()
            stats = data.get('stats', [])
            for stat in stats:
                if stat['key'] == 'cluster.capacity.total':
                    capacity_total.set(stat['value'])
                elif stat['key'] == 'cluster.capacity.used':
                    capacity_used.set(stat['value'])
                elif stat['key'] == 'cluster.capacity.free':
                    capacity_free.set(stat['value'])
    
    def _collect_performance(self):
        """Collect performance metrics"""
        response = self.session.get(f"{self.base_url}/1/statistics/current?key=cluster.protostats.*")
        if response.status_code == 200:
            data = response.json()
            stats = data.get('stats', [])
            for stat in stats:
                if stat['key'] == 'cluster.protostats.iops':
                    iops_total.set(stat['value'])
                elif stat['key'] == 'cluster.protostats.throughput.read':
                    throughput_read.set(stat['value'])
                elif stat['key'] == 'cluster.protostats.throughput.write':
                    throughput_write.set(stat['value'])

def main():
    """Main function"""
    logger.info(f"Starting Isilon exporter on port {METRICS_PORT}")
    logger.info(f"Connecting to Isilon at {ISILON_HOST}")
    
    # Start metrics server
    start_http_server(METRICS_PORT)
    
    # Create collector
    collector = IsilonCollector()
    
    # Collect metrics every 30 seconds
    while True:
        collector.collect_metrics()
        time.sleep(30)

if __name__ == '__main__':
    main()
```

## Usage Examples

### 1. Quick Start with Auto-Detection
```bash
# Clone the repository
git clone https://github.com/odin-monitoring/odin-standalone
cd odin-standalone

# Run with auto-detection
./scripts/odin-deploy.sh --auto-detect
```

### 2. Deploy Storage Monitoring
```bash
# Set storage configuration
export ISILON_HOST=192.168.1.100
export ISILON_USER=monitor
export ISILON_PASS=secure_password

# Deploy with storage profile
./scripts/odin-deploy.sh --profile storage

# Verify storage metrics
curl http://localhost:9117/metrics | grep isilon_
```

### 3. Deploy Gaming Profile
```bash
# Ensure NVIDIA runtime is installed
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# Deploy gaming profile
./scripts/odin-deploy.sh --profile gaming

# Access GPU dashboard
open http://localhost:3000/d/gpu-overview
```

### 4. Custom Deployment
```bash
# Create custom environment
cp profiles/.env.base profiles/.env.custom
vim profiles/.env.custom  # Edit as needed

# Deploy with custom profile
PROFILE=custom ./scripts/odin-deploy.sh
```

### 5. Backup and Restore
```bash
# Backup current deployment
./scripts/backup-restore.sh backup

# Restore from backup
./scripts/backup-restore.sh restore --backup-id 20250530_120000
```

## Single Binary Distribution

For even simpler deployment, we can compile ODIN into a single binary:

```go
// cmd/odin/main.go
package main

import (
    "embed"
    "flag"
    "log"
    "os"
    "os/exec"
)

//go:embed configs templates docker-compose.yml
var embeddedFiles embed.FS

func main() {
    profile := flag.String("profile", "base", "Deployment profile")
    autoDetect := flag.Bool("auto-detect", false, "Auto-detect hardware")
    flag.Parse()
    
    // Extract embedded files
    extractFiles()
    
    // Run deployment
    cmd := exec.Command("./scripts/odin-deploy.sh", 
        "--profile", *profile)
    if *autoDetect {
        cmd.Args = append(cmd.Args, "--auto-detect")
    }
    
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    
    if err := cmd.Run(); err != nil {
        log.Fatal(err)
    }
}
```

Build and distribute:
```bash
# Build single binary
go build -o odin cmd/odin/main.go

# Deploy anywhere
./odin --profile storage --auto-detect
```

## Advantages of This Approach

1. **No Kubernetes Required**: Runs on any Docker-capable system
2. **Simple Deployment**: One script to rule them all
3. **Profile-Based**: Easy to customize for different environments
4. **Auto-Detection**: Intelligent hardware detection
5. **Portable**: Can be packaged as a single binary
6. **Resource Efficient**: Minimal overhead compared to k8s

## Next Steps

1. Create the actual Docker images for custom exporters
2. Build comprehensive dashboard library
3. Add more auto-detection capabilities
4. Create web-based configuration UI
5. Package as system packages (deb, rpm)