#!/usr/bin/env bash
set -u

RESTART_LIBVIRT=false
VM=""
VM_ACTION=""
VM_AUTOSTART=""
NETWORK=""
START_NETWORK=false
POOL=""
START_POOL=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage(){ cat <<'EOF'
Usage: kvm_virtualization_repair.sh [options]

  --restart-libvirt            Restart and verify the installed libvirt daemon.
  --vm NAME --action ACTION    Start, reboot, shutdown, resume or reset one VM.
  --vm-autostart NAME on|off   Enable or disable autostart for one VM.
  --start-network NAME         Start and enable autostart for one libvirt network.
  --start-pool NAME            Start and enable autostart for one storage pool.
  --dry-run                    Show commands without changing virtualization state.
  --yes                        Skip confirmation prompts.
  --output DIR                 Save logs and before/after evidence in DIR.
EOF
}
while [ "$#" -gt 0 ]; do case "$1" in
  --restart-libvirt) RESTART_LIBVIRT=true; shift;; --vm) VM="${2:-}"; shift 2;;
  --action) VM_ACTION="${2:-}"; shift 2;; --vm-autostart) VM="${2:-}"; VM_AUTOSTART="${3:-}"; shift 3;;
  --start-network) NETWORK="${2:-}"; START_NETWORK=true; shift 2;; --start-pool) POOL="${2:-}"; START_POOL=true; shift 2;;
  --dry-run) DRY_RUN=true; shift;; --yes) ASSUME_YES=true; shift;;
  --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;; esac; done
if ! $RESTART_LIBVIRT && [ -z "$VM" ] && ! $START_NETWORK && ! $START_POOL; then echo "Choose at least one repair action." >&2; exit 2; fi
command -v virsh >/dev/null 2>&1 || { echo "virsh is required." >&2; exit 3; }
if [ -n "$VM" ]; then virsh dominfo "$VM" >/dev/null 2>&1 || { echo "VM not found: $VM" >&2; exit 2; }; fi
if [ -n "$VM_ACTION" ]; then case "$VM_ACTION" in start|reboot|shutdown|resume|reset) :;; *) echo "Unsupported VM action." >&2; exit 2;; esac; fi
if [ -n "$VM_AUTOSTART" ]; then case "$VM_AUTOSTART" in on|off) :;; *) echo "VM autostart value must be on or off." >&2; exit 2;; esac; fi
if $START_NETWORK; then virsh net-info "$NETWORK" >/dev/null 2>&1 || { echo "Network not found: $NETWORK" >&2; exit 2; }; fi
if $START_POOL; then virsh pool-info "$POOL" >/dev/null 2>&1 || { echo "Pool not found: $POOL" >&2; exit 2; }; fi
SERVICE=""; for u in libvirtd.service virtqemud.service; do systemctl list-unit-files "$u" >/dev/null 2>&1 && { SERVICE="$u"; break; }; done
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./kvm-repair-$STAMP}"; mkdir -p "$OUTPUT_DIR"; LOG="$OUTPUT_DIR/repair.log"; BEFORE="$OUTPUT_DIR/before.txt"; AFTER="$OUTPUT_DIR/after.txt"; : >"$LOG"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
confirm(){ $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
run(){ local d="$1"; shift; ACTIONS=$((ACTIONS+1)); log "$d"; if $DRY_RUN; then printf 'DRY-RUN:' >>"$LOG"; printf ' %q' "$@" >>"$LOG"; printf '\n' >>"$LOG"; return 0; fi; if "$@" >>"$LOG" 2>&1; then log "SUCCESS: $d"; else FAILURES=$((FAILURES+1)); log "WARNING: $d failed"; return 1; fi; }
root(){ local d="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run "$d" "$@"; else run "$d" sudo "$@"; fi; }
collect(){ local f="$1"; { echo "Collected: $(date -Is)"; [ -n "$SERVICE" ] && systemctl status "$SERVICE" --no-pager -l 2>&1 || true; echo; virsh list --all 2>&1 || true; virsh net-list --all 2>&1 || true; virsh pool-list --all 2>&1 || true; [ -n "$VM" ] && { echo; virsh dominfo "$VM" 2>&1 || true; }; } >"$f"; }
collect "$BEFORE"; confirm "Apply the selected KVM and libvirt repairs? Virtual machines may be interrupted." || { log "Repair cancelled."; exit 10; }
if $RESTART_LIBVIRT; then [ -n "$SERVICE" ] && root "Restarting $SERVICE" systemctl restart "$SERVICE" || { FAILURES=$((FAILURES+1)); log "WARNING: libvirt service not found."; }; fi
if [ -n "$VM_ACTION" ]; then case "$VM_ACTION" in start) root "Starting VM $VM" virsh start "$VM" || true;; reboot) root "Rebooting VM $VM" virsh reboot "$VM" || true;; shutdown) root "Shutting down VM $VM" virsh shutdown "$VM" || true;; resume) root "Resuming VM $VM" virsh resume "$VM" || true;; reset) confirm "Reset VM $VM immediately? Unsaved guest data may be lost." && root "Resetting VM $VM" virsh reset "$VM" || true;; esac; fi
if [ -n "$VM_AUTOSTART" ]; then [ "$VM_AUTOSTART" = on ] && root "Enabling autostart for $VM" virsh autostart "$VM" || root "Disabling autostart for $VM" virsh autostart --disable "$VM" || true; fi
if $START_NETWORK; then root "Starting network $NETWORK" virsh net-start "$NETWORK" || true; root "Enabling autostart for network $NETWORK" virsh net-autostart "$NETWORK" || true; fi
if $START_POOL; then root "Starting storage pool $POOL" virsh pool-start "$POOL" || true; root "Enabling autostart for pool $POOL" virsh pool-autostart "$POOL" || true; fi
$DRY_RUN || sleep 3; collect "$AFTER"; [ "$FAILURES" -eq 0 ] || exit 20; log "Virtualization repair completed successfully. Actions performed: $ACTIONS"
