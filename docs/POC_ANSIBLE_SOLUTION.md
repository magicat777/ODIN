# Proof of Concept: ODIN Ansible-Based Deployment

## Overview

This POC demonstrates an enterprise-grade ODIN deployment using Ansible for configuration management, suitable for large-scale infrastructure monitoring.

## Directory Structure

```
odin-ansible/
├── ansible.cfg                 # Ansible configuration
├── requirements.yml           # Galaxy dependencies
├── site.yml                   # Main playbook
├── playbooks/
│   ├── detect-hardware.yml    # Hardware detection
│   ├── deploy-core.yml        # Core services deployment
│   ├── configure-exporters.yml # Exporter configuration
│   ├── generate-dashboards.yml # Dashboard generation
│   └── health-check.yml       # Post-deployment validation
├── inventories/
│   ├── production/
│   │   ├── hosts.yml          # Static inventory
│   │   ├── group_vars/
│   │   │   ├── all.yml        # Global variables
│   │   │   ├── monitoring_servers.yml
│   │   │   ├── storage_nodes.yml
│   │   │   └── gaming_systems.yml
│   │   └── host_vars/
│   │       ├── razerblade18.yml
│   │       └── isilon-cluster.yml
│   ├── staging/
│   └── dynamic/
│       └── inventory.py       # Dynamic inventory script
├── roles/
│   ├── odin_common/          # Common configurations
│   ├── odin_prometheus/      # Prometheus deployment
│   ├── odin_grafana/         # Grafana deployment
│   ├── odin_exporters/       # Exporter management
│   ├── odin_dashboards/      # Dashboard provisioning
│   └── odin_profiles/        # Profile management
├── templates/
│   ├── prometheus/
│   ├── grafana/
│   └── exporters/
├── files/
│   ├── dashboards/
│   └── rules/
├── filter_plugins/           # Custom Jinja2 filters
├── library/                  # Custom modules
└── tests/
    ├── test-inventory.yml
    └── test-deployment.yml
```

## Core Files

### ansible.cfg
```ini
[defaults]
inventory = inventories/production/hosts.yml
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
stdout_callback = yaml
callback_whitelist = profile_tasks, timer
roles_path = roles
library = library
filter_plugins = filter_plugins

[inventory]
enable_plugins = yaml, ini, script, auto

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-%%h-%%p-%%r
```

### site.yml (Main Playbook)
```yaml
---
# ODIN Monitoring Stack Deployment
- name: ODIN Pre-flight Checks
  hosts: all
  gather_facts: yes
  tags: [always]
  tasks:
    - name: Verify Ansible version
      assert:
        that:
          - ansible_version.full is version('2.9', '>=')
        fail_msg: "Ansible 2.9 or higher is required"
    
    - name: Detect ODIN profile if not set
      include_role:
        name: odin_profiles
        tasks_from: detect.yml
      when: odin_profile is not defined

- name: Deploy ODIN Core Components
  hosts: monitoring_servers
  become: yes
  tags: [core]
  roles:
    - role: odin_common
      tags: [common]
    - role: odin_prometheus
      tags: [prometheus]
      when: odin_components.prometheus | default(true)
    - role: odin_grafana
      tags: [grafana]
      when: odin_components.grafana | default(true)
    - role: odin_loki
      tags: [loki]
      when: odin_components.loki | default(true)

- name: Deploy ODIN Exporters
  hosts: all:!monitoring_servers
  become: yes
  tags: [exporters]
  roles:
    - role: odin_exporters
      odin_exporter_list: "{{ odin_profile_exporters[odin_profile] }}"

- name: Configure Dashboards and Alerts
  hosts: monitoring_servers
  become: yes
  tags: [configure]
  roles:
    - role: odin_dashboards
      tags: [dashboards]
    - role: odin_alerts
      tags: [alerts]

- name: Post-Deployment Health Check
  hosts: monitoring_servers
  tags: [verify]
  tasks:
    - import_playbook: playbooks/health-check.yml
```

### Inventory Structure

#### inventories/production/hosts.yml
```yaml
all:
  children:
    monitoring_servers:
      hosts:
        monitor-01:
          ansible_host: 10.0.1.10
          odin_role: primary
        monitor-02:
          ansible_host: 10.0.1.11
          odin_role: secondary
    
    storage_nodes:
      hosts:
        isilon-01:
          ansible_host: 10.0.2.10
          odin_storage_type: isilon
          odin_storage_api: https://10.0.2.10:8080
        nas-01:
          ansible_host: 10.0.2.20
          odin_storage_type: generic_nfs
    
    gaming_systems:
      hosts:
        razerblade18:
          ansible_host: 192.168.1.100
          odin_gpu_present: true
          odin_gpu_type: nvidia_rtx4090
          odin_razer_devices:
            - keyboard
            - mouse
    
    web_servers:
      hosts:
        web-[01:10]:
          ansible_host: 10.0.3.{{ item }}
      vars:
        odin_monitor_nginx: true
        odin_monitor_php_fpm: true
```

#### inventories/dynamic/inventory.py
```python
#!/usr/bin/env python3
"""
Dynamic inventory script for ODIN
Discovers infrastructure and assigns appropriate monitoring profiles
"""

import json
import subprocess
import socket
import os
from typing import Dict, List, Any

class OdinInventory:
    def __init__(self):
        self.inventory = {
            '_meta': {
                'hostvars': {}
            }
        }
        self.discovered_hosts = []
    
    def discover_network(self, subnet: str = '10.0.0.0/16') -> List[str]:
        """Discover hosts on network using nmap"""
        try:
            result = subprocess.run(
                ['nmap', '-sn', subnet, '-oG', '-'],
                capture_output=True,
                text=True
            )
            
            hosts = []
            for line in result.stdout.split('\n'):
                if 'Host:' in line and 'Status: Up' in line:
                    ip = line.split()[1]
                    hosts.append(ip)
            
            return hosts
        except Exception as e:
            print(f"Network discovery failed: {e}")
            return []
    
    def detect_host_type(self, host: str) -> Dict[str, Any]:
        """Detect host type and capabilities"""
        host_info = {
            'ansible_host': host,
            'odin_profile': 'base'
        }
        
        # Try to detect services
        services = self.scan_ports(host)
        
        # Storage detection
        if 8080 in services or 'isilon' in socket.getfqdn(host).lower():
            host_info['odin_profile'] = 'storage'
            host_info['odin_storage_type'] = 'isilon'
            host_info['odin_storage_api'] = f'https://{host}:8080'
        
        # Database detection
        if 3306 in services or 5432 in services:
            host_info['odin_monitor_database'] = True
            host_info['odin_database_type'] = 'mysql' if 3306 in services else 'postgresql'
        
        # Web server detection
        if 80 in services or 443 in services:
            host_info['odin_monitor_web'] = True
        
        return host_info
    
    def scan_ports(self, host: str, ports: List[int] = None) -> List[int]:
        """Quick port scan to detect services"""
        if ports is None:
            ports = [22, 80, 443, 3306, 5432, 8080, 9090, 3000]
        
        open_ports = []
        for port in ports:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex((host, port))
            if result == 0:
                open_ports.append(port)
            sock.close()
        
        return open_ports
    
    def generate_inventory(self):
        """Generate dynamic inventory"""
        # Discover hosts
        if os.environ.get('ODIN_DISCOVER_NETWORK'):
            subnet = os.environ.get('ODIN_SUBNET', '10.0.0.0/16')
            self.discovered_hosts = self.discover_network(subnet)
        
        # Categorize hosts
        for host in self.discovered_hosts:
            host_info = self.detect_host_type(host)
            profile = host_info['odin_profile']
            
            # Add to appropriate group
            if profile not in self.inventory:
                self.inventory[profile] = {'hosts': []}
            
            hostname = f"discovered-{host.replace('.', '-')}"
            self.inventory[profile]['hosts'].append(hostname)
            self.inventory['_meta']['hostvars'][hostname] = host_info
        
        # Add static groups
        self.add_static_groups()
        
        return self.inventory
    
    def add_static_groups(self):
        """Add static group definitions"""
        self.inventory['all'] = {
            'children': list(self.inventory.keys())
        }
        self.inventory['all'].pop('_meta', None)

def main():
    inventory = OdinInventory()
    print(json.dumps(inventory.generate_inventory(), indent=2))

if __name__ == '__main__':
    main()
```

### Role Examples

#### roles/odin_profiles/tasks/detect.yml
```yaml
---
- name: Gather hardware facts
  setup:
    gather_subset:
      - hardware
      - network
      - virtual

- name: Detect NVIDIA GPU
  shell: lspci | grep -i nvidia
  register: nvidia_check
  failed_when: false
  changed_when: false

- name: Detect Razer hardware
  shell: lsusb | grep -i razer
  register: razer_check
  failed_when: false
  changed_when: false

- name: Check for Isilon/PowerScale
  uri:
    url: "https://{{ ansible_default_ipv4.address }}:8080/platform/1/cluster/config"
    method: GET
    validate_certs: no
    timeout: 2
  register: isilon_check
  failed_when: false
  when: odin_profile is not defined

- name: Detect system profile
  set_fact:
    odin_profile: >-
      {%- if nvidia_check.rc == 0 and razer_check.rc == 0 -%}
        gaming
      {%- elif isilon_check is defined and isilon_check.status == 200 -%}
        storage
      {%- elif ansible_memtotal_mb > 32768 and ansible_processor_vcpus > 8 -%}
        enterprise
      {%- elif ansible_virtualization_role == 'guest' -%}
        vm
      {%- else -%}
        base
      {%- endif -%}
  when: odin_profile is not defined

- name: Display detected profile
  debug:
    msg: "Detected ODIN profile: {{ odin_profile }}"
```

#### roles/odin_prometheus/tasks/main.yml
```yaml
---
- name: Create Prometheus user
  user:
    name: prometheus
    system: yes
    shell: /sbin/nologin
    home: /var/lib/prometheus
    create_home: no

- name: Create Prometheus directories
  file:
    path: "{{ item }}"
    state: directory
    owner: prometheus
    group: prometheus
    mode: '0755'
  loop:
    - /etc/prometheus
    - /var/lib/prometheus
    - /etc/prometheus/rules
    - /etc/prometheus/file_sd

- name: Download Prometheus
  unarchive:
    src: "https://github.com/prometheus/prometheus/releases/download/v{{ prometheus_version }}/prometheus-{{ prometheus_version }}.linux-amd64.tar.gz"
    dest: /tmp
    remote_src: yes
    owner: prometheus
    group: prometheus
  register: prometheus_download

- name: Install Prometheus binaries
  copy:
    src: "/tmp/prometheus-{{ prometheus_version }}.linux-amd64/{{ item }}"
    dest: "/usr/local/bin/{{ item }}"
    owner: prometheus
    group: prometheus
    mode: '0755'
    remote_src: yes
  loop:
    - prometheus
    - promtool

- name: Generate Prometheus configuration
  template:
    src: prometheus.yml.j2
    dest: /etc/prometheus/prometheus.yml
    owner: prometheus
    group: prometheus
    mode: '0644'
    backup: yes
  notify: restart prometheus

- name: Create Prometheus service
  template:
    src: prometheus.service.j2
    dest: /etc/systemd/system/prometheus.service
  notify:
    - reload systemd
    - restart prometheus

- name: Configure firewall for Prometheus
  firewalld:
    port: 9090/tcp
    permanent: yes
    state: enabled
    immediate: yes
  when: ansible_facts['os_family'] == "RedHat"

- name: Start and enable Prometheus
  systemd:
    name: prometheus
    state: started
    enabled: yes
    daemon_reload: yes
```

#### roles/odin_exporters/tasks/main.yml
```yaml
---
- name: Deploy exporters based on profile
  include_tasks: "deploy_{{ item }}.yml"
  loop: "{{ odin_exporter_list }}"
  when: odin_exporter_list is defined

- name: Deploy node exporter (default)
  include_tasks: deploy_node_exporter.yml
  when: "'node_exporter' in odin_default_exporters"

- name: Deploy storage exporters
  include_tasks: deploy_storage_exporters.yml
  when: 
    - odin_profile == 'storage'
    - odin_storage_type is defined

- name: Deploy GPU exporters
  include_tasks: deploy_gpu_exporters.yml
  when:
    - odin_profile in ['gaming', 'enterprise']
    - odin_gpu_present | default(false)

- name: Configure Prometheus targets
  template:
    src: "file_sd/{{ odin_profile }}_targets.yml.j2"
    dest: "/etc/prometheus/file_sd/{{ inventory_hostname }}_targets.yml"
  delegate_to: "{{ item }}"
  loop: "{{ groups['monitoring_servers'] }}"
  notify: reload prometheus
```

#### roles/odin_exporters/tasks/deploy_storage_exporters.yml
```yaml
---
- name: Deploy SNMP exporter for storage
  block:
    - name: Install SNMP exporter
      unarchive:
        src: "https://github.com/prometheus/snmp_exporter/releases/download/v{{ snmp_exporter_version }}/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64.tar.gz"
        dest: /tmp
        remote_src: yes
    
    - name: Copy SNMP exporter binary
      copy:
        src: "/tmp/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64/snmp_exporter"
        dest: /usr/local/bin/snmp_exporter
        mode: '0755'
        remote_src: yes
    
    - name: Generate SNMP configuration
      template:
        src: snmp/{{ odin_storage_type }}.yml.j2
        dest: /etc/snmp_exporter/snmp.yml
      notify: restart snmp_exporter
  when: odin_storage_type in ['isilon', 'netapp', 'emc']

- name: Deploy custom Isilon exporter
  block:
    - name: Create Isilon exporter directory
      file:
        path: /opt/odin/exporters/isilon
        state: directory
    
    - name: Copy Isilon exporter script
      template:
        src: exporters/isilon_exporter.py.j2
        dest: /opt/odin/exporters/isilon/isilon_exporter.py
        mode: '0755'
    
    - name: Create Isilon exporter service
      template:
        src: systemd/isilon_exporter.service.j2
        dest: /etc/systemd/system/isilon_exporter.service
      notify:
        - reload systemd
        - restart isilon_exporter
  when: odin_storage_type == 'isilon'
```

### Profile Variables

#### inventories/production/group_vars/all.yml
```yaml
---
# ODIN Global Configuration
odin_version: "1.0.0"
odin_deployment_name: "production"

# Component versions
prometheus_version: "2.45.0"
grafana_version: "10.0.0"
alertmanager_version: "0.26.0"
loki_version: "2.9.0"
node_exporter_version: "1.6.0"
snmp_exporter_version: "0.24.1"

# Default components
odin_components:
  prometheus: true
  grafana: true
  alertmanager: true
  loki: true

# Profile definitions
odin_profiles:
  base:
    exporters:
      - node_exporter
    dashboards:
      - system-overview
      - node-metrics
    retention: "30d"
    scrape_interval: "30s"
  
  storage:
    exporters:
      - node_exporter
      - snmp_exporter
      - storage_api_exporter
    dashboards:
      - system-overview
      - storage-overview
      - isilon-performance
      - capacity-planning
    retention: "90d"
    scrape_interval: "15s"
  
  gaming:
    exporters:
      - node_exporter
      - nvidia_gpu_exporter
      - razer_exporter
    dashboards:
      - system-overview
      - gpu-performance
      - thermal-monitoring
      - gaming-metrics
    retention: "7d"
    scrape_interval: "10s"
  
  enterprise:
    exporters:
      - node_exporter
      - process_exporter
      - blackbox_exporter
      - snmp_exporter
    dashboards:
      - system-overview
      - business-metrics
      - sla-monitoring
      - capacity-planning
    retention: "365d"
    scrape_interval: "30s"

# Exporter configurations
odin_exporter_configs:
  node_exporter:
    port: 9100
    collectors:
      - cpu
      - diskstats
      - filesystem
      - loadavg
      - meminfo
      - netdev
      - stat
      - time
      - uname
  
  nvidia_gpu_exporter:
    port: 9400
    metrics:
      - temperature
      - utilization
      - memory
      - power
  
  storage_api_exporter:
    port: 9117
    api_version: "1.0"
    metrics_path: "/metrics"
```

### Templates

#### templates/prometheus/prometheus.yml.j2
```yaml
# Prometheus configuration for {{ odin_deployment_name }}
# Profile: {{ odin_profile }}
# Generated by Ansible

global:
  scrape_interval: {{ odin_profiles[odin_profile].scrape_interval }}
  evaluation_interval: 30s
  external_labels:
    cluster: '{{ odin_deployment_name }}'
    profile: '{{ odin_profile }}'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
{% for host in groups['monitoring_servers'] %}
          - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:9093
{% endfor %}

# Rule files
rule_files:
  - '/etc/prometheus/rules/*.yml'

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node exporter
  - job_name: 'node'
    file_sd_configs:
      - files:
          - '/etc/prometheus/file_sd/*_node_targets.yml'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: '${1}'

{% if odin_profile == 'storage' %}
  # Storage monitoring
  - job_name: 'storage_snmp'
    static_configs:
      - targets:
{% for host in groups['storage_nodes'] %}
        - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:161
{% endfor %}
    metrics_path: /snmp
    params:
      module: [{{ odin_storage_type }}_metrics]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: {{ ansible_default_ipv4.address }}:9116

  # Isilon API metrics
  - job_name: 'isilon_api'
    static_configs:
      - targets:
{% for host in groups['storage_nodes'] %}
{% if hostvars[host]['odin_storage_type'] == 'isilon' %}
        - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:9117
{% endif %}
{% endfor %}
{% endif %}

{% if odin_profile == 'gaming' %}
  # GPU monitoring
  - job_name: 'nvidia_gpu'
    static_configs:
      - targets:
{% for host in groups['gaming_systems'] %}
{% if hostvars[host]['odin_gpu_present'] | default(false) %}
        - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:9400
{% endif %}
{% endfor %}
{% endif %}

  # Service discovery for dynamic targets
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
```

### Deployment Commands

#### Deploy to All Systems
```bash
# Full deployment with auto-detection
ansible-playbook site.yml

# Deploy specific profile
ansible-playbook site.yml -e odin_profile=storage

# Deploy to specific group only
ansible-playbook site.yml --limit storage_nodes
```

#### Profile-Specific Deployments
```bash
# Deploy storage monitoring to Isilon clusters
ansible-playbook site.yml \
  --limit storage_nodes \
  -e odin_profile=storage \
  -e odin_storage_type=isilon

# Deploy gaming profile to specific host
ansible-playbook site.yml \
  --limit razerblade18 \
  -e odin_profile=gaming \
  -e odin_gpu_present=true

# Enterprise deployment with HA
ansible-playbook site.yml \
  -e odin_profile=enterprise \
  -e odin_ha_enabled=true \
  -e odin_retention=365d
```

#### Testing and Validation
```bash
# Dry run
ansible-playbook site.yml --check

# Test specific role
ansible-playbook site.yml --tags prometheus --check

# Validate deployment
ansible-playbook playbooks/health-check.yml
```

### Advanced Features

#### Custom Module: odin_dashboard
```python
#!/usr/bin/python
# library/odin_dashboard.py

from ansible.module_utils.basic import AnsibleModule
import json
import requests

def generate_dashboard(profile, metrics):
    """Generate Grafana dashboard based on profile and available metrics"""
    dashboard = {
        "dashboard": {
            "title": f"ODIN {profile.title()} Overview",
            "panels": []
        }
    }
    
    # Add panels based on available metrics
    panel_id = 1
    for metric in metrics:
        panel = {
            "id": panel_id,
            "title": metric['title'],
            "type": metric.get('type', 'graph'),
            "targets": [{
                "expr": metric['expr'],
                "refId": "A"
            }],
            "gridPos": {
                "x": ((panel_id - 1) % 2) * 12,
                "y": ((panel_id - 1) // 2) * 8,
                "w": 12,
                "h": 8
            }
        }
        dashboard['dashboard']['panels'].append(panel)
        panel_id += 1
    
    return dashboard

def main():
    module = AnsibleModule(
        argument_spec=dict(
            profile=dict(type='str', required=True),
            metrics=dict(type='list', required=True),
            grafana_url=dict(type='str', required=True),
            grafana_api_key=dict(type='str', required=True, no_log=True),
            state=dict(type='str', default='present', choices=['present', 'absent'])
        )
    )
    
    profile = module.params['profile']
    metrics = module.params['metrics']
    grafana_url = module.params['grafana_url']
    api_key = module.params['grafana_api_key']
    state = module.params['state']
    
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }
    
    if state == 'present':
        dashboard = generate_dashboard(profile, metrics)
        
        response = requests.post(
            f"{grafana_url}/api/dashboards/db",
            headers=headers,
            json=dashboard
        )
        
        if response.status_code == 200:
            module.exit_json(changed=True, dashboard_id=response.json()['id'])
        else:
            module.fail_json(msg=f"Failed to create dashboard: {response.text}")
    
    elif state == 'absent':
        # Delete dashboard logic
        pass

if __name__ == '__main__':
    main()
```

#### Inventory Plugin for Cloud Providers
```python
# inventory_plugins/odin_cloud.py

from ansible.plugins.inventory import BaseInventoryPlugin
import boto3  # For AWS
from azure.mgmt.compute import ComputeManagementClient  # For Azure
from google.cloud import compute_v1  # For GCP

class InventoryModule(BaseInventoryPlugin):
    NAME = 'odin_cloud'
    
    def parse(self, inventory, loader, path, cache=True):
        super(InventoryModule, self).parse(inventory, loader, path, cache)
        
        config = self._read_config_data(path)
        
        # Detect cloud provider
        if config.get('aws_enabled'):
            self._populate_from_aws(config)
        if config.get('azure_enabled'):
            self._populate_from_azure(config)
        if config.get('gcp_enabled'):
            self._populate_from_gcp(config)
    
    def _populate_from_aws(self, config):
        """Populate inventory from AWS EC2"""
        ec2 = boto3.resource('ec2', region_name=config.get('aws_region'))
        
        for instance in ec2.instances.filter(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]):
            hostname = instance.id
            self.inventory.add_host(hostname)
            
            # Detect profile based on instance type
            if instance.instance_type.startswith('p3') or instance.instance_type.startswith('g4'):
                self.inventory.set_variable(hostname, 'odin_profile', 'gaming')
                self.inventory.set_variable(hostname, 'odin_gpu_present', True)
            elif instance.instance_type.startswith('m5'):
                self.inventory.set_variable(hostname, 'odin_profile', 'enterprise')
            
            # Set connection info
            self.inventory.set_variable(hostname, 'ansible_host', instance.public_ip_address)
            self.inventory.set_variable(hostname, 'ansible_user', 'ec2-user')
```

## Advantages of This Approach

1. **Infrastructure as Code**: Complete deployment defined in code
2. **Idempotent**: Safe to run multiple times
3. **Scalable**: From single host to thousands
4. **Flexible**: Easy to extend with custom modules and plugins
5. **No Container Dependency**: Can deploy native binaries
6. **Enterprise Features**: Integration with existing infrastructure

## Integration Examples

### With Terraform
```hcl
# Deploy infrastructure and configure monitoring
resource "null_resource" "odin_deployment" {
  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i inventory/dynamic/inventory.py site.yml \
        -e odin_profile=${var.monitoring_profile} \
        -e odin_deployment_name=${var.environment}
    EOT
  }
  
  depends_on = [
    aws_instance.monitoring_servers,
    aws_instance.application_servers
  ]
}
```

### With CI/CD
```yaml
# .gitlab-ci.yml
deploy_monitoring:
  stage: deploy
  script:
    - ansible-playbook site.yml -i $INVENTORY -e odin_profile=$PROFILE
  environment:
    name: production
  only:
    - main
```

## Next Steps

1. Create Ansible Galaxy collection for easy distribution
2. Develop more cloud inventory plugins
3. Add molecule tests for roles
4. Create AWX/Tower job templates
5. Build compliance checking playbooks