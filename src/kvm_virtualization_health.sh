#!/usr/bin/env bash
set -u

HOURS=24
OUTPUT_DIR=""

usage() {
  echo "Usage: kvm_virtualization_health.sh [--hours N] [--output DIR]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./kvm-health-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/kvm-health.txt"
CSV="$OUTPUT_DIR/virtual-machines.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"
echo 'name,state,autostart,vcpus,memory_kib' > "$CSV"

section() {
  local title="$1"
  shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

section "Metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; uname -a; id'
section "CPU virtualization support" bash -c 'lscpu | grep -Ei "Virtualization|Hypervisor|Model name|Socket|Core|Thread"; grep -Eoc "(vmx|svm)" /proc/cpuinfo || true'
section "KVM modules" bash -c 'lsmod | grep -E "^kvm" || true; modinfo kvm 2>/dev/null | head -n 100 || true'
section "libvirt services" bash -c 'systemctl status libvirtd virtqemud virtnetworkd virtstoraged --no-pager -l 2>/dev/null || true'
section "Host capacity" bash -c 'free -h; df -hT; lscpu; uptime'
section "Network bridges" bash -c 'ip -brief link; bridge link 2>/dev/null || brctl show 2>/dev/null || true'
section "Recent virtualization events" bash -c "journalctl --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'libvirt|qemu|kvm|virtqemud|migration|domain.*error' | tail -n 3000 || true"

LIBVIRT_AVAILABLE=false
if command -v virsh >/dev/null 2>&1 && virsh list --all >/dev/null 2>&1; then
  LIBVIRT_AVAILABLE=true
  section "Virtual machines" virsh list --all
  section "Storage pools" virsh pool-list --all
  section "Storage volumes" bash -c 'for p in $(virsh pool-list --all --name); do [[ -n "$p" ]] || continue; echo "--- $p"; virsh vol-list "$p"; done'
  section "Virtual networks" virsh net-list --all
  section "Host interfaces" virsh iface-list --all

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    state="$(virsh domstate "$name" 2>>"$ERRORS" | tr '\n' ' ')"
    autostart="$(virsh dominfo "$name" 2>>"$ERRORS" | awk -F: '/Autostart/{gsub(/^[[:space:]]+/,"",$2); print $2}')"
    vcpus="$(virsh dominfo "$name" 2>>"$ERRORS" | awk -F: '/CPU.s./{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
    memory="$(virsh dominfo "$name" 2>>"$ERRORS" | awk -F: '/Max memory/{gsub(/^[[:space:]]+/,"",$2); print $2}' | awk '{print $1}')"
    printf '"%s","%s","%s",%s,%s\n' "$name" "$state" "${autostart:-unknown}" "${vcpus:-0}" "${memory:-0}" >> "$CSV"
    section "Domain details: $name" virsh dominfo "$name"
    section "Domain block devices: $name" virsh domblklist "$name" --details
    section "Domain interfaces: $name" virsh domiflist "$name"
    section "Domain snapshots: $name" virsh snapshot-list "$name"
  done < <(virsh list --all --name 2>>"$ERRORS")
fi

KVM_SUPPORTED=false
grep -Eq '(vmx|svm)' /proc/cpuinfo && KVM_SUPPORTED=true
KVM_MODULE_LOADED=false
lsmod | grep -q '^kvm' && KVM_MODULE_LOADED=true
LIBVIRT_ACTIVE=false
if systemctl is-active --quiet libvirtd 2>/dev/null || systemctl is-active --quiet virtqemud 2>/dev/null; then LIBVIRT_ACTIVE=true; fi
VM_COUNT="$(awk 'END {print NR-1}' "$CSV")"
RUNNING_VMS="$(awk -F, 'NR>1 && $2 ~ /running/ {c++} END {print c+0}' "$CSV")"
OVERALL="Healthy"
if ! $KVM_SUPPORTED || ! $KVM_MODULE_LOADED; then OVERALL="Attention required"; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "cpu_virtualization_supported": $KVM_SUPPORTED,
  "kvm_module_loaded": $KVM_MODULE_LOADED,
  "libvirt_available": $LIBVIRT_AVAILABLE,
  "libvirt_service_active": $LIBVIRT_ACTIVE,
  "virtual_machines": $VM_COUNT,
  "running_virtual_machines": $RUNNING_VMS,
  "overall_status": "$OVERALL"
}
EOF

printf '\nKVM and virtualization health collection completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
