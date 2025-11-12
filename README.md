# containers 📦

## Run Windows 11 container (libvirt + Vagrant) 🪟🐧

> Disclaimer: This workflow has been tested on Fedora Linux only. It has not been validated on macOS or Windows hosts.

### Build the image (optional if you pull a prebuilt image) 🏗️

```bash
podman build -t win-vagrant /home/sdelacru/repos/containers/win
# Or pull prebuilt:
# podman pull quay.io/sdelacru/flightctl-win:v1
```

### Run the container 🚀

Recommended (host networking + host cgroups):

```bash
sudo podman run --privileged -it --name win11 --replace \
  --cgroupns=host --security-opt seccomp=unconfined \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  --device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  --network=host \
  win-vagrant /bin/bash
# For prebuilt:
# quay.io/sdelacru/flightctl-win:v1
```

Alternative (bridge networking + published RDP ports) 🌉:

```bash
sudo podman run --privileged -it --name win11 --replace \
  --cgroupns=host --security-opt seccomp=unconfined \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  --device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  --network bridge -p 53389:53389 -p 53390:53390 \
  win-vagrant /bin/bash
```

### Inside the container 🧰

```bash
bash /home/user/startup.sh
```

What it does:
- 🚌 Starts D-Bus and libvirtd, ensures default libvirt network is active
- 🔐 Sets iptables for NAT and RDP forwarding
- 🧪 Boots the Windows 11 Vagrant box under libvirt
- 🔁 Enables RDP in the guest and sets up rsync of `/home/user` to `C:\Users\Vagrant`

### Connect via RDP 🖥️

- Windows 11: `localhost:53389`
- Credentials: usually `vagrant` / `vagrant` (per box defaults)

### Troubleshooting 🛠️

- Cgroup errors (machine.slice) → ensure `--cgroupns=host` and mount `/sys/fs/cgroup:rw`
- Permission denied on NVRAM → script prepares `/var/lib/libvirt/qemu/nvram/win_uefi_vars.fd`
- KVM not available → verify `/dev/kvm` exists on host and is passed into the container

### Troubleshooting matrix (common libvirt/QEMU errors) 🧭

| Symptom (log/excerpt) | Likely cause | Fix | Verify |
| --- | --- | --- | --- |
| cannot limit core file size ... Operation not permitted | libvirt tries to set unlimited core size in restricted env | Set `max_core = 0` in `/etc/libvirt/qemu.conf`, restart libvirt | `grep max_core /etc/libvirt/qemu.conf`; `systemctl status libvirtd` or `pgrep libvirtd` |
| Failed to acquire pid file '/run/libvirt/.../driver.pid' | Stale PID file or conflicting daemon | Stop daemons, remove PID files, start only `libvirtd` | `sudo pkill libvirtd virtqemud virtnetworkd virtinterfaced`; `ls /run/libvirt/*/driver.pid` |
| could not load PC BIOS '/usr/share/ovmf/OVMF.fd' | Missing/wrong OVMF path | `sudo dnf -y install edk2-ovmf`; set `libvirt.loader` to a valid `OVMF_CODE*.fd` | `ls /usr/share/edk2/ovmf/*OVMF_CODE*.fd` |
| Permission denied opening OVMF_VARS*.fd | QEMU trying to write `/usr/share` VARS | Copy VARS to `/var/lib/libvirt/qemu/nvram/*.fd`; point `libvirt.nvram` to it | `ls -l /var/lib/libvirt/qemu/nvram/*.fd` (owner `qemu:qemu`) |
| unable to open '/sys/fs/cgroup/machine/...' (No such file) | Container lacks writable cgroup v2 | Run container with `--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw` | `mount | grep /sys/fs/cgroup`; `test -w /sys/fs/cgroup` |
| QEMU unexpectedly closed the monitor | Generic failure: firmware, perms, devices | Check firmware paths, NVRAM perms, pass `/dev/kvm`, inspect QEMU log | `ls -l /dev/kvm`; review `/var/log/libvirt/qemu/*.log` |
| Authorization not available (polkit) | polkit not available in container | Set `auth_unix_ro/rw = "none"` in `/etc/libvirt/libvirtd.conf` | `grep auth_unix_ /etc/libvirt/libvirtd.conf` |
| Mounting NFS shared folders on Windows fails | Windows guest lacks NFS capability | Disable default synced folder; use rsync or SMB | `config.vm.synced_folder ".", "/vagrant", disabled: true` |
| KVM: permission denied / not present | `/dev/kvm` not available or not passed | Run container with `--device=/dev/kvm`; ensure user in `kvm` | `ls -l /dev/kvm`; `id` shows `kvm` group |
| Network 'default' is not active | Libvirt default network down | `virsh net-define` (if needed) and `virsh net-start default` | `virsh net-list --all` shows `default active` |

## Run all Flightctl VMs with make-vm.sh ✈️

The `make-vm.sh` script builds a bootable image per release directory (e.g., `centos9`, `rhel96`, `rhel96_fips`) and then creates/boots a libvirt VM.

Prerequisites (host):
- 🐋 Podman, qemu-kvm, libvirt, virt-install
- 🌐 Network access to OpenShift and flightctl endpoints
- 💾 Sufficient disk space (each VM image ~ several GB)

Run for a single release:

```bash
# From repo root
./make-vm.sh centos9
# or
./make-vm.sh rhel96
# or
./make-vm.sh rhel96_fips
```

Run all supported releases:

```bash
for r in centos9 rhel96 rhel96_fips; do
  ./make-vm.sh "$r"
done
```

What the script does:
- 🔑 Logs into OpenShift and flightctl using embedded endpoints/tokens
- 🏗️ Builds the container image under the selected release directory
- 🧱 Uses bootc-image-builder to generate a qcow2
- ▶️ Imports and expands the qcow2, then launches a transient libvirt VM:
  - 🏷️ VM name: `flightctl-<release>`
  - 💽 Disk path: `/var/lib/libvirt/images/flightctl-<release>.qcow2`

Manage VMs 🧑‍✈️:

```bash
# List
virsh list --all

# Stop and remove a VM (example: centos9)
VM=flightctl-centos9
virsh destroy "$VM" 2>/dev/null || true
virsh undefine "$VM" 2>/dev/null || true
sudo rm -f "/var/lib/libvirt/images/${VM}.qcow2"
```

Notes:
- 🐧 The script currently targets Linux releases; the `win/` directory is separate and uses Vagrant/libvirt inside a container (see section above).
- ⚙️ If you need to override endpoints or tokens, edit `make-vm.sh` variables at the top (`OPENSHIFT_API`, `OPENSHIFT_TOKEN`, `FLIGHTCTL_API`) or export env vars that the helper finders (`OC_BIN`, `FLIGHTCTL_BIN`) respect. 

## TODO ✅

- Validate container flow on RHEL, Fedora Silverblue, and Ubuntu hosts.
- Rootless mode: investigate libvirt-in-container feasibility without `--privileged`.
- Replace iptables with firewalld/nftables-aware rules where available.
- Improve Windows rsync: switch to push-on-change or periodic sync; exclude more locked paths.
- Optional SMB path (documented) for non-RDP workflows.
- Parameterize CPU/RAM and RDP ports via env vars in `startup.sh`.
- Add cleanup script to remove VMs, networks, and temporary NVRAM files.
- Cache/prefetch Vagrant boxes in image build with version pins.

