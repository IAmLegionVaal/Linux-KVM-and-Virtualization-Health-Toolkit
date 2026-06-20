# Linux KVM and Virtualization Health Toolkit

A read-only Bash toolkit for collecting KVM, libvirt, virtual machine, storage pool, network bridge, snapshot, and host-capacity evidence.

## Usage

```bash
chmod +x src/kvm_virtualization_health.sh
sudo ./src/kvm_virtualization_health.sh
```

## Checks performed

- CPU virtualization support and KVM kernel modules
- libvirt service and daemon state
- Virtual machines, states, autostart settings, vCPU, memory, and disks
- Storage pools, volumes, networks, interfaces, and snapshots
- Host CPU, memory, disk, and bridge health
- Recent libvirt, QEMU, and KVM events
- Text, CSV, and JSON reports

## Safety

The script never starts, stops, pauses, migrates, snapshots, edits, or deletes virtual machines and resources.

## Author

Dewald Pretorius — L2 IT Support Engineer
