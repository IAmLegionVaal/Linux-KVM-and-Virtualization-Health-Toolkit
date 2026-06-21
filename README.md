# Linux KVM and Virtualization Health Toolkit

A Linux support toolkit for diagnosing KVM and libvirt problems and applying selected guarded repairs.

## Diagnostic script

```bash
chmod +x src/kvm_virtualization_health.sh
sudo ./src/kvm_virtualization_health.sh
```

## Repair script

```bash
chmod +x src/kvm_virtualization_repair.sh
sudo ./src/kvm_virtualization_repair.sh --restart-libvirt --dry-run
```

Examples:

```bash
sudo ./src/kvm_virtualization_repair.sh --restart-libvirt
sudo ./src/kvm_virtualization_repair.sh --vm web01 --action start
sudo ./src/kvm_virtualization_repair.sh --vm web01 --action reboot
sudo ./src/kvm_virtualization_repair.sh --vm-autostart web01 on
sudo ./src/kvm_virtualization_repair.sh --start-network default
sudo ./src/kvm_virtualization_repair.sh --start-pool default
```

## What the repair does

- Restarts the installed libvirt or virtqemud service.
- Starts, reboots, shuts down, resumes or explicitly resets one selected VM.
- Enables or disables autostart for one selected VM.
- Starts and enables autostart for one selected libvirt network or storage pool.
- Captures service, VM, network and pool state before and after repair.
- Requires an extra confirmation before a forceful VM reset.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

VM restart, shutdown and reset actions can interrupt workloads. The tool does not delete, redefine, migrate, snapshot or alter VM disks and configuration automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
