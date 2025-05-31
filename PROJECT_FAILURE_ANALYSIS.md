# ODIN Monitoring Stack Failure Analysis & Recovery Plan

## Executive Summary

The ODIN monitoring stack, which was operating at 95% production deployment with Docker Desktop for Linux, has suffered a catastrophic failure due to an unintended migration of all containers from Docker Desktop to the local Docker context. This has resulted in complete loss of connectivity between 14 services and Grafana dashboards showing "no data" across all metrics.

## Current State Analysis

### What Was Working (Before Migration)
- 14 containers fully operational in Docker Desktop context
- All exporters (Node, GPU, Docker, Claude, etc.) functioning
- Grafana dashboards displaying real-time metrics
- Prometheus successfully scraping all targets
- Integrated logging with Loki/Promtail
- GPU monitoring with NVIDIA SDK support
- AlertManager configured and operational

### Current Failure State
- Mixed deployment: some services in containers, others as systemd services
- Network connectivity broken between container and host services
- All Grafana dashboards showing "No data"
- GPU exporter port conflicts (9101 vs 9836)
- Prometheus moved to host but containers can't reach it
- Docker networking issues (`host.docker.internal` not working)
- Configuration drift between expected and actual deployment

## Root Cause Analysis

### Primary Cause
**Accidental Docker Context Switch**: While attempting to move a single NVIDIA GPU-enabled LLM container to local Docker context, all containers were inadvertently migrated from Docker Desktop to native Docker.

### Contributing Factors

1. **Network Architecture Incompatibility**
   - Docker Desktop provides `host.docker.internal` for container-to-host communication
   - Native Docker on Linux doesn't support this hostname
   - Attempted workarounds (172.17.0.1, host network mode) created more complexity

2. **Hybrid Deployment Model**
   - Partial migration to systemd services created split-brain architecture
   - Services expecting containers found systemd services instead
   - Port conflicts between different deployment methods

3. **Configuration Management**
   - No centralized configuration management
   - Manual updates to multiple configuration files
   - Lost track of which services should be containers vs host services

4. **Lack of Rollback Plan**
   - No backup of working Docker Desktop configuration
   - No documented procedure for context switching
   - Changes made incrementally without testing complete stack

## Technical Issues Encountered

1. **Container Networking**
   - `host.docker.internal` resolution failure
   - Bridge network IP addresses changing
   - Container-to-host communication broken

2. **Service Discovery**
   - Prometheus unable to find host-based exporters from container
   - Grafana unable to reach host-based Prometheus
   - Services hardcoded with Docker Desktop assumptions

3. **Port Conflicts**
   - Multiple GPU exporters attempting same ports
   - Systemd services conflicting with container ports
   - No port allocation strategy

4. **Configuration Drift**
   - Prometheus scrape configs pointing to wrong addresses
   - Grafana datasources using incorrect endpoints
   - Dashboard variables not updated for new architecture

## Best Path Forward

### Option 1: Full Docker Desktop Restoration (Recommended)

**Advantages:**
- Return to known working state
- `host.docker.internal` works out of the box
- Simplified networking model
- GPU passthrough proven to work

**Implementation Steps:**
1. Stop all systemd services for exporters
2. Switch back to Docker Desktop context
3. Restore original docker-compose configurations
4. Use Docker Desktop's GPU support for NVIDIA containers
5. Implement proper backup strategy

### Option 2: Native Docker with Proper Architecture

**Advantages:**
- Better performance
- More control over networking
- Native systemd integration
- Direct GPU access

**Implementation Requirements:**
1. Complete architecture redesign
2. All services in containers OR all on host (not mixed)
3. Proper service mesh or overlay network
4. Service discovery solution (Consul, etcd)
5. Configuration management (Ansible, Terraform)

### Option 3: Kubernetes-Based Solution

**Advantages:**
- Industry standard for container orchestration
- Built-in service discovery
- Declarative configuration
- Easy rollback and updates

**Components:**
- K3s or MicroK8s for single-node
- Helm charts for monitoring stack
- NVIDIA device plugin for GPU support
- Persistent volumes for data

## Recommended Recovery Plan

### Immediate Actions (Return to Operational State)

1. **Document Current State**
   ```bash
   docker context use desktop-linux
   docker ps -a > docker-desktop-state.txt
   systemctl list-units --type=service | grep exporter > systemd-state.txt
   ```

2. **Stop All Systemd Exporters**
   ```bash
   systemctl stop prometheus node-exporter nvidia-gpu-exporter claude-exporter
   systemctl disable prometheus node-exporter nvidia-gpu-exporter claude-exporter
   ```

3. **Return to Docker Desktop**
   ```bash
   docker context use desktop-linux
   ```

4. **Restore Original Compose Files**
   - Use git to revert to last known working configuration
   - Restore environment variables
   - Verify volume mounts

5. **Start Services in Correct Order**
   ```bash
   docker-compose -f docker-compose.yml up -d
   docker-compose -f docker-compose-exporters.yml up -d
   docker-compose -f docker-compose-logging.yml up -d
   ```

### Long-Term Solution Architecture

```yaml
# Proposed docker-compose structure
version: '3.8'

networks:
  odin:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  # Core monitoring stack
  prometheus:
    image: prom/prometheus:latest
    networks:
      - odin
    extra_hosts:
      - "host.docker.internal:host-gateway"
    
  grafana:
    image: grafana/grafana:latest
    networks:
      - odin
    environment:
      - GF_RENDERING_SERVER_URL=http://renderer:8081/render
      
  # All exporters as containers
  node-exporter:
    image: prom/node-exporter:latest
    networks:
      - odin
    pid: host
    
  nvidia-exporter:
    image: nvidia/dcgm-exporter:latest
    networks:
      - odin
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
```

### Monitoring Best Practices

1. **Configuration Management**
   - Use environment files for configuration
   - Version control all configurations
   - Document all custom modifications

2. **Deployment Strategy**
   - Choose ONE deployment method (containers OR systemd)
   - Use health checks for all services
   - Implement proper restart policies

3. **Backup and Recovery**
   - Regular backups of Prometheus data
   - Grafana dashboard exports
   - Configuration snapshots
   - Documented recovery procedures

4. **GPU Monitoring**
   - Use official NVIDIA DCGM exporter
   - Configure proper GPU runtime
   - Monitor GPU memory, utilization, and temperature

## Lessons Learned

1. **Never mix Docker contexts without careful planning**
2. **Maintain consistent deployment architecture**
3. **Document before making infrastructure changes**
4. **Test migrations in isolated environment first**
5. **Keep rollback procedures ready**
6. **Use infrastructure as code principles**

## Conclusion

The current state represents a classic case of incremental changes leading to architectural drift. The recommended approach is to return to Docker Desktop for immediate recovery, then plan a proper migration to native Docker or Kubernetes if desired. The key is maintaining architectural consistency and avoiding hybrid deployments that create complexity without benefit.

## Next Steps

1. Make a decision on recovery approach
2. Schedule maintenance window
3. Execute recovery plan with rollback capability
4. Document final architecture
5. Implement monitoring for the monitoring stack
6. Create runbooks for common operations