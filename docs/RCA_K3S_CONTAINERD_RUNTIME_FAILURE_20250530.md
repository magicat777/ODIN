# Root Cause Analysis: K3s Cluster Failure After Reboot

**Date**: May 30, 2025  
**Severity**: High  
**Duration**: ~2 hours  
**Impact**: Complete ODIN monitoring stack outage  

## Executive Summary

After a system reboot, the K3s cluster failed to start properly due to a containerd runtime configuration conflict. The issue was caused by modifications made to support NVIDIA GPU runtime for the swrpg-gen project, which inadvertently removed the default runtime configuration required by K3s.

## Timeline of Events

1. **Pre-incident**: Attempted to enable NVIDIA CUDA support in K3s for swrpg-gen project
2. **Configuration Change**: Modified `/etc/containerd/config.toml` to add nvidia runtime
3. **Reboot**: System rebooted to fix stuck K3s cluster
4. **Failure**: K3s failed to start with CRI plugin initialization errors
5. **Detection**: ODIN health check showed cluster not accessible
6. **Resolution**: Fixed containerd config and switched to embedded containerd

## Root Cause

### Primary Cause: Containerd Runtime Misconfiguration

The `/etc/containerd/config.toml` was modified to only include the nvidia runtime:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
```

**Missing**: The default "runc" runtime that K3s expects:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "runc"
  
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"
```

### Contributing Factors

1. **K3s Service Override**: `/etc/systemd/system/k3s.service.d/gpu.conf` pointed K3s to external containerd
2. **Deprecated Feature Gates**: Configuration included `DevicePlugins=true` which is no longer valid
3. **Service Dependencies**: No explicit dependency between k3s.service and containerd.service
4. **Duplicate Exporters**: Both host-based and container-based exporters configured on same ports

## Impact Analysis

- **K3s API Server**: Unavailable
- **All Kubernetes Workloads**: Unable to start (CNI not initialized)
- **Monitoring Stack**: Complete outage
- **Data Loss**: None (persistent volumes intact)

## Resolution Steps Taken

1. Identified CRI plugin failure in containerd logs
2. Fixed `/etc/containerd/config.toml` to include both runc and nvidia runtimes
3. Removed deprecated DevicePlugins feature gates
4. Switched to K3s embedded containerd for stability
5. Removed duplicate exporter deployments

## Lessons Learned

### What Went Well
- Quick identification of root cause through log analysis
- No data loss during the incident
- Clean resolution without requiring cluster rebuild

### What Went Wrong
- Configuration changes not tested with service restart before reboot
- No configuration backup before making changes
- Incomplete understanding of containerd runtime requirements

## Action Items

### Immediate Actions (Completed)
- [x] Fix containerd configuration
- [x] Remove deprecated K3s feature gates
- [x] Delete duplicate exporter deployments
- [x] Verify cluster health

### Future Prevention Measures

1. **Configuration Management**
   - Always backup configurations before modifications
   - Test changes with service restart before reboot
   - Document all configuration changes in CLAUDE.md

2. **GPU Support Best Practices**
   - Use K3s embedded containerd when possible
   - If external containerd required, ensure both runtimes configured:
     ```toml
     [plugins."io.containerd.grpc.v1.cri".containerd]
       default_runtime_name = "runc"
       
     [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
       [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
         runtime_type = "io.containerd.runc.v2"
         
       [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
         runtime_type = "io.containerd.runc.v2"
         [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
           BinaryName = "/usr/bin/nvidia-container-runtime"
     ```

3. **Monitoring Improvements**
   - Add pre-reboot validation script
   - Monitor containerd CRI plugin status
   - Alert on k3s restart loops

4. **Documentation Updates**
   - Create GPU configuration guide
   - Document runtime configuration requirements
   - Add troubleshooting guide for CRI failures

## Correct GPU Configuration for K3s

For future NVIDIA GPU support in K3s, use one of these approaches:

### Option 1: K3s Embedded Containerd (Recommended)
```bash
# Create nvidia runtime configuration
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/
sudo tee /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl <<EOF
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
EOF

# Restart k3s
sudo systemctl restart k3s
```

### Option 2: External Containerd with Both Runtimes
Ensure the configuration includes BOTH runc (default) and nvidia runtimes as shown above.

## Validation Checklist

Before rebooting after runtime configuration changes:

- [ ] Verify containerd config: `sudo containerd config dump | grep runtime`
- [ ] Test service restart: `sudo systemctl restart containerd && sudo systemctl restart k3s`
- [ ] Check node status: `kubectl get nodes`
- [ ] Verify runtime: `kubectl describe node | grep -i runtime`
- [ ] Test GPU access: `kubectl run nvidia-smi --rm -it --restart=Never --image=nvidia/cuda:11.6.2-base-ubuntu20.04 -- nvidia-smi`

## References

- [K3s GPU Support Documentation](https://docs.k3s.io/advanced#nvidia-container-runtime-support)
- [Containerd Runtime Configuration](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

---
**Document Version**: 1.0  
**Last Updated**: May 30, 2025  
**Author**: Claude (ODIN Administrator)