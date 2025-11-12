#!/bin/bash
set -euo pipefail
echo "setting max_core to 0"
sudo grep -q "^[[:space:]]*max_core" /etc/libvirt/qemu.conf \
  && sudo sed -ri "s/^[[:space:]]*#?[[:space:]]*max_core[[:space:]]*=.*/max_core = 0/" /etc/libvirt/qemu.conf \
  || echo "max_core = 0" | sudo tee -a /etc/libvirt/qemu.conf >/dev/null
echo "setting max_core to 0 (session)"
mkdir -p "$HOME/.config/libvirt"
if [ -f "$HOME/.config/libvirt/qemu.conf" ] && grep -q "^[[:space:]]*max_core" "$HOME/.config/libvirt/qemu.conf"; then
  sed -ri "s/^[[:space:]]*#?[[:space:]]*max_core[[:space:]]*=.*/max_core = 0/" "$HOME/.config/libvirt/qemu.conf"
else
  echo "max_core = 0" >> "$HOME/.config/libvirt/qemu.conf"
fi
echo "killing processes"
sudo pkill libvirtd || true
sudo pkill virtqemud || true
sudo pkill virtnetworkd || true
sudo pkill virtinterfaced || true
sudo pkill dbus-daemon || true
sudo pkill virtlogd || true
sleep 3
echo "delete pids"
sudo rm -f /run/libvirt/qemu/driver.pid
sudo rm -f /run/libvirt/network/driver.pid
sudo rm -f /run/libvirt/interface/driver.pid
sudo rm -f /run/virtqemud.pid
sudo rm -f /run/libvirtd.pid
sudo rm -f /run/virtnetworkd.pid
sudo rm -f /run/virtinterfaced.pid
sudo rm -f /run/dbus/pid
sudo rm -f /run/libvirt/secrets/driver.pid
sudo rm -f /run/libvirt/storage/driver.pid
sudo rm -f /run/libvirt/nodedev/driver.pid
sudo rm -f /run/libvirt/nwfilter/driver.pid
sudo rm -f /run/libvirt/network/driver.pid
sudo rm -f /run/virtlogd.pid
echo "setting libvirt auth to none"
# Set libvirt auth to "none" (in case it reset)
sudo sed -i 's/#auth_unix_ro = "polkit"/auth_unix_ro = "none"/' /etc/libvirt/libvirtd.conf
sudo sed -i 's/#auth_unix_rw = "polkit"/auth_unix_rw = "none"/' /etc/libvirt/libvirtd.conf
echo "cgroup_controllers = []" | sudo tee -a /etc/libvirt/libvirtd.conf > /dev/null
echo "--- Configs applied ---"
echo "Create directories"
# Create required directories
sudo mkdir -p /run/dbus
sudo mkdir -p /var/lib/dbus
echo "starting DBus"
# 1. Start D-Bus
sudo dbus-uuidgen --ensure=/var/lib/dbus/machine-id
sudo /usr/bin/dbus-daemon --system &
sleep 2
echo "starting libvirt"
# 2. Start Libvirt (Wait 2 seconds)
sleep 2
sudo /usr/sbin/libvirtd &
sleep 3
# Prepare writable OVMF NVRAM for VMs
echo "preparing writable OVMF NVRAM under /var/lib/libvirt/qemu/nvram"
sudo mkdir -p /var/lib/libvirt/qemu/nvram
# Pick a VARS template
OVMF_VARS=""
for CAND in /usr/share/edk2/ovmf/OVMF_VARS.secboot.fd /usr/share/edk2/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/x64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd; do
  if [ -f "$CAND" ]; then OVMF_VARS="$CAND"; break; fi
done
if [ -n "$OVMF_VARS" ]; then
  if [ ! -f /var/lib/libvirt/qemu/nvram/win_uefi_vars.fd ]; then
    sudo cp "$OVMF_VARS" /var/lib/libvirt/qemu/nvram/win_uefi_vars.fd
  fi
  sudo chown qemu:qemu /var/lib/libvirt/qemu/nvram/win_uefi_vars.fd || true
  sudo chmod 0644 /var/lib/libvirt/qemu/nvram/win_uefi_vars.fd || true
  if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon -v /var/lib/libvirt/qemu/nvram/win_uefi_vars.fd || true
  fi
else
  echo "warning: no OVMF_VARS template found; UEFI NVRAM might fail"
fi
sudo /usr/sbin/virtlogd &
sleep 2
# Ensure default network exists and is active; avoid restarting if active
if ! sudo virsh net-info default >/dev/null 2>&1; then
  echo "default network missing, trying to define and start"
  if [ -f /usr/share/libvirt/networks/default.xml ]; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
  fi
fi
if ! sudo virsh net-list --all | grep -qE '^\s*default\s'; then
  echo "default network not defined; skipping start"
else
  if ! sudo virsh net-list | grep -qE '^\s*default\s'; then
    sudo virsh net-start default || true
  fi
  sudo virsh net-autostart default || true
  echo "--- Default network ready ---"
fi
echo "configuring iptables (NAT and RDP on virbr0)"
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
# Detect outbound interface
EXT_IF="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
[ -z "$EXT_IF" ] && EXT_IF="eth0"
# NAT for libvirt default network 192.168.122.0/24
if ! sudo iptables -t nat -C POSTROUTING -s 192.168.122.0/24 -o "$EXT_IF" -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -s 192.168.122.0/24 -o "$EXT_IF" -j MASQUERADE
fi
# Forwarding rules between virbr0 and outbound interface
if ! sudo iptables -C FORWARD -i virbr0 -o "$EXT_IF" -j ACCEPT 2>/dev/null; then
  sudo iptables -I FORWARD -i virbr0 -o "$EXT_IF" -j ACCEPT
fi
if ! sudo iptables -C FORWARD -i "$EXT_IF" -o virbr0 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
  sudo iptables -I FORWARD -i "$EXT_IF" -o virbr0 -m state --state ESTABLISHED,RELATED -j ACCEPT
fi
# Allow NEW RDP connections from external iface to VMs on virbr0 (for DNAT)
if ! sudo iptables -C FORWARD -i "$EXT_IF" -o virbr0 -p tcp --dport 3389 -j ACCEPT 2>/dev/null; then
  sudo iptables -I FORWARD -i "$EXT_IF" -o virbr0 -p tcp --dport 3389 -j ACCEPT
fi
# Allow inbound RDP to forwarded host ports (53389 for win11, 53390 for win10 by default)
for PORT in 53389 53390; do
  if ! sudo iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
  fi
done

echo "starting vagrant box"
vagrant up

echo "configuring RDP host port forwarding to guest(s)"
# Helper: extract IPv4 for a hostname from libvirt default network leases
get_vm_ip() {
  local vm_host="$1"
  sudo virsh net-dhcp-leases default 2>/dev/null \
    | awk -v h="$vm_host" '
      /ipv4/ && $0 ~ h {
        for (i=1;i<=NF;i++) {
          if ($i ~ /\/[0-9]+$/) { split($i,a,"/"); print a[1]; exit }
        }
      }'
}
# Helper: add DNAT for local and external traffic
ensure_rdp_forward() {
  local host_port="$1"
  local dest_ip="$2"
  local dest_port="3389"
  # External connections
  if ! sudo iptables -t nat -C PREROUTING -p tcp --dport "${host_port}" -j DNAT --to-destination "${dest_ip}:${dest_port}" 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp --dport "${host_port}" -j DNAT --to-destination "${dest_ip}:${dest_port}"
  fi
  # Local host connections
  if ! sudo iptables -t nat -C OUTPUT -p tcp --dport "${host_port}" -j DNAT --to-destination "${dest_ip}:${dest_port}" 2>/dev/null; then
    sudo iptables -t nat -A OUTPUT -p tcp --dport "${host_port}" -j DNAT --to-destination "${dest_ip}:${dest_port}"
  fi
}
# Wait briefly for DHCP leases to appear
sleep 2
WIN11_IP="$(get_vm_ip win11 || true)"
if [ -n "${WIN11_IP:-}" ]; then
  echo "win11 IP detected: ${WIN11_IP}; forwarding host:53389 -> ${WIN11_IP}:3389"
  ensure_rdp_forward 53389 "${WIN11_IP}"
fi
WIN10_IP="$(get_vm_ip win10 || true)"
if [ -n "${WIN10_IP:-}" ]; then
  echo "win10 IP detected: ${WIN10_IP}; forwarding host:53390 -> ${WIN10_IP}:3389"
  ensure_rdp_forward 53390 "${WIN10_IP}"
fi
# Enable OpenSSH and rsync on Windows guests via WinRM, then rsync /home/user -> C:\Users\Vagrant
enable_ssh_and_rsync_ps='
$ErrorActionPreference = "SilentlyContinue"
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (Inbound)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
}
choco install -y rsync
'
echo "enabling OpenSSH + rsync in guest(s) via WinRM"
if [ -n "${WIN11_IP:-}" ]; then
  vagrant winrm win11 -c "$enable_ssh_and_rsync_ps" || true
fi
if [ -n "${WIN10_IP:-}" ]; then
  vagrant winrm win10 -c "$enable_ssh_and_rsync_ps" || true
fi
# Wait for SSH to be reachable and push rsync
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
  # sync /home/user -> C:\Users\Vagrant using cygwin path
  EXCLUDES=(--exclude 'AppData/**' --exclude 'NTUSER.DAT*' --exclude 'ntuser.dat*' --exclude 'UsrClass.dat*' --exclude 'Recent/**' --exclude 'Temp/**')
  sshpass -p vagrant rsync -az --delete "${EXCLUDES[@]}" -e "ssh -p $port $SSH_OPTS" /home/user/ vagrant@"$ip":/cygdrive/c/Users/Vagrant/
}
if [ -n "${WIN11_IP:-}" ]; then
  echo "rsync /home/user -> win11:C:\\Users\\Vagrant"
  rsync_to_vm "${WIN11_IP}"
fi
if [ -n "${WIN10_IP:-}" ]; then
  echo "rsync /home/user -> win10:C:\\Users\\Vagrant"
  rsync_to_vm "${WIN10_IP}"
fi
# Try to resolve the libvirt domain name and guest IP for the Vagrant box
exec "$@"
