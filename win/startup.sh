#!/bin/bash
set -euo pipefail

HOST_SYNC_DIR="${HOST_SYNC_DIR:-/home/user}"
echo "📂 Using host sync directory: ${HOST_SYNC_DIR}"
echo "♻️ Bringing up Vagrant box (win11)"
echo "📦 Ensuring base box is available"
vagrant plugin install vagrant-libvirt vagrant-reload winrm winrm-elevated --local
vagrant box list | grep -q '^oopsme/windows11-22h2' || vagrant box add --provider libvirt --box-version 11-22h2-uefi --clean oopsme/windows11-22h2
vagrant up

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3"
rsync_to_vm() {
  local ip="$1"
  local port="${2:-22}"
  # wait up to ~60s for ssh
  for i in $(seq 1 30); do
    if ssh -p "$port" $SSH_OPTS vagrant@"$ip" "echo ok" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  EXCLUDES=(--exclude 'AppData/**' --exclude 'NTUSER.DAT*' --exclude 'ntuser.dat*' --exclude 'UsrClass.dat*' --exclude 'Recent/**' --exclude 'Temp/**')
  sshpass -p vagrant rsync -az --delete "${EXCLUDES[@]}" -e "ssh -p $port $SSH_OPTS" "${HOST_SYNC_DIR}/" vagrant@"$ip":/cygdrive/c/Users/Vagrant/
}
if [ -n "${WIN11_IP:-}" ]; then
  echo "🔁 rsync ${HOST_SYNC_DIR} -> win11:C:\\Users\\Vagrant"
  rsync_to_vm "${WIN11_IP}"
  vagrant winrm win11 -e -s powershell -c "powershell -ExecutionPolicy Bypass -File 'C:\\Users\\Vagrant\\scripts\\flightctl-login.ps1" || true
  vagrant winrm win11 -e -s powershell -c "powershell -ExecutionPolicy Bypass -File 'C:\\Users\\Vagrant\\scripts\\get-devices.ps1" || true
fi
if command -v expect >/dev/null 2>&1; then
  echo "🔄 Starting vagrant rsync-auto in background"
  cd "${HOST_SYNC_DIR}"
  (
    expect <<'EOF'
spawn vagrant rsync-auto
expect {
  "password:" {
    send "vagrant\r"
    exp_continue
  }
  eof
}
EOF
  ) &
  RSYNC_AUTO_PID=$!
  echo "✅ vagrant rsync-auto started (PID: $RSYNC_AUTO_PID)"
else
  echo "⚠️ 'expect' not found; skipping vagrant rsync-auto. Install 'expect' to enable auto-sync."
fi

exec "$@"
