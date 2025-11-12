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
```

Prebuilt image:

```bash
sudo podman run --privileged -it --name win11 --replace \
  --cgroupns=host --security-opt seccomp=unconfined \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  --device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  --network=host \
  quay.io/sdelacru/flightctl-win:v1 /bin/bash
```

Alternative (bridge networking + published SPICE port) 🌉:

```bash
sudo podman run --privileged -it --name win11 --replace \
  --cgroupns=host --security-opt seccomp=unconfined \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  --device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  --network bridge -p 5930:5930 -e SPICE_LISTEN=0.0.0.0 \
  win-vagrant /bin/bash
```

Prebuilt image:

```bash
sudo podman run --privileged -it --name win11 --replace \
  --cgroupns=host --security-opt seccomp=unconfined \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  --device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  --network bridge -p 5930:5930 -e SPICE_LISTEN=0.0.0.0 \
  quay.io/sdelacru/flightctl-win:v1 /bin/bash
```

### Inside the container 🧰

```bash
bash /home/user/startup.sh
```

What it does:
- 🚌 Starts D-Bus and libvirtd, ensures default libvirt network is active
- 🔐 Configures libvirt default NAT networking; SPICE graphics is enabled
- 🧪 Boots the Windows 11 Vagrant box under libvirt
- 🔁 Sets up rsync of `/home/user` to `C:\Users\Vagrant`

### Connect via SPICE 🖥️

- With host networking: `remote-viewer spice://127.0.0.1:5930`
- With bridge networking: publish `-p 5930:5930` and run container with `-e SPICE_LISTEN=0.0.0.0`, then `remote-viewer spice://127.0.0.1:5930`
- Tip: Install SPICE guest tools in Windows for better display/clipboard

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

### Constraints and assumptions ⚠️

- Linux host only; tested on Fedora 43+ (not validated on macOS or Windows).
- Requires hardware virtualization (VT-x/AMD-V) and host `/dev/kvm` access.
- Container must run privileged with host cgroups and devices:
  - `--privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw`
  - Devices: `--device=/dev/kvm --device=/dev/net/tun --device=/dev/vhost-net`
  - Caps: `--cap-add=NET_ADMIN --cap-add=SYS_ADMIN`
- Verify RW cgroup mount inside the container:
  ```bash
  mount | grep ' /sys/fs/cgroup ' || true
  [ -w /sys/fs/cgroup ] && echo "OK: /sys/fs/cgroup is writable" || echo "ERROR: /sys/fs/cgroup is not writable"
  ```
- Networking assumes libvirt default NAT network; host networking is recommended for simplicity.
- Rootless mode is not supported (no TAP/bridge, limited cgroups/devices).
- UEFI firmware required on host: `edk2-ovmf` provides `OVMF_CODE*` and `OVMF_VARS*`.
- SELinux/AppArmor may require permissive policies or proper labeling; seccomp is set to unconfined in run examples.
- Windows rsync excludes are applied to avoid locked profile files; large syncs may be slow.

## Generate qcow2 images from container images 🖼️

This repository contains bootc-based container images that can be converted to qcow2 disk images for use with libvirt, QEMU, or other virtualization platforms.

### Prerequisites

- 🐋 Podman (for building and running containers)
- 🧱 bootc-image-builder (available as a container image)
- 💾 Sufficient disk space (each qcow2 image is several GB)

### Automated generation (via make-vm.sh)

The `make-vm.sh` script automates the entire process including qcow2 generation. See the [Run all Flightctl VMs](#run-all-flightctl-vms-with-make-vmsh-) section below.

### Manual qcow2 generation

To generate a qcow2 image manually from a container image:

1. **Build the container image** from a release directory:

```bash
cd centos9  # or rhel96, rhel96_fips
podman build -t quay.io/sdelacru/centos9:v1 .
```

2. **Generate the qcow2 image** using bootc-image-builder:

```bash
mkdir -p output
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${PWD}/output":/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    quay.io/sdelacru/centos9:v1
```

The qcow2 image will be available at `output/qcow2/disk.qcow2`.

**Note for Fedora bootc-based images**: When building Fedora bootc images, pass `--rootfs btrfs` to avoid rootless rootfs errors:

```bash
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${PWD}/output":/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --rootfs btrfs \
    <your-image-ref>
```

3. **Use the qcow2 image** with libvirt or QEMU:

```bash
# Copy to libvirt images directory
sudo cp output/qcow2/disk.qcow2 /var/lib/libvirt/images/my-vm.qcow2

# Optionally resize the disk
sudo qemu-img resize /var/lib/libvirt/images/my-vm.qcow2 +20G

# Set proper ownership
sudo chown libvirt:libvirt /var/lib/libvirt/images/my-vm.qcow2
```

### What bootc-image-builder does

The `bootc-image-builder` container:
- Takes a bootc-based container image as input
- Extracts the filesystem and boot configuration
- Creates a bootable disk image in the specified format (qcow2, raw, etc.)
- Outputs the image to the mounted `/output` directory

The generated qcow2 images are ready to boot in VMs and include:
- The complete filesystem from the container image
- Boot configuration (GRUB, systemd-boot, etc.)
- All installed packages and configurations
- Flightctl agent (if included in the container image)

## Publish images to quay.io 📤

After building container images, you can publish them to quay.io for distribution and reuse.

### Prerequisites

- 🐋 Podman installed and configured
- 🔐 quay.io account with access to the target repository
- 🔑 quay.io authentication token (or logged in via `podman login`)

### Manual publishing

1. **Login to quay.io**:

```bash
podman login quay.io
# Enter your quay.io username and password/token when prompted
```

Alternatively, use a token:

```bash
echo "YOUR_QUAY_TOKEN" | podman login quay.io --username YOUR_USERNAME --password-stdin
```

2. **Build and tag the image** with your quay.io repository:

```bash
# For Windows container
cd win
podman build -t quay.io/YOUR_USERNAME/your-image-win:v1 .

# For Linux containers (example: centos9)
cd centos9
podman build -t quay.io/YOUR_USERNAME/your-image-centos9:v1 .
```

3. **Push the image** to quay.io:

```bash
# Push Windows image
podman push quay.io/YOUR_USERNAME/your-image-win:v1

# Push Linux image
podman push quay.io/YOUR_USERNAME/your-image-centos9:v1
```

### Publishing multiple images

To publish all images at once:

```bash
# Set your quay.io username
QUAY_USER="your-username"
VERSION="v1"

# Build and push each image
for dir in centos9 rhel96 rhel96_fips win; do
  cd "$dir"
  IMAGE_NAME="your-image-${dir}"
  podman build -t "quay.io/${QUAY_USER}/${IMAGE_NAME}:${VERSION}" .
  podman push "quay.io/${QUAY_USER}/${IMAGE_NAME}:${VERSION}"
  cd ..
done
```

### Tagging strategies

Common tagging approaches:

- **Version tags**: `v1`, `v1.0.0`, `latest`
- **Branch-based**: `main`, `develop`
- **Commit-based**: Use short commit SHA: `git rev-parse --short HEAD`

Example with multiple tags:

```bash
VERSION="v1.0.0"
COMMIT=$(git rev-parse --short HEAD)
IMAGE="quay.io/YOUR_USERNAME/your-image-centos9"

podman build -t "${IMAGE}:${VERSION}" \
             -t "${IMAGE}:${COMMIT}" \
             -t "${IMAGE}:latest" \
             centos9

podman push "${IMAGE}:${VERSION}"
podman push "${IMAGE}:${COMMIT}"
podman push "${IMAGE}:latest"
```

### Using published images

Once published, others can pull and use your images:

```bash
# Pull the image
podman pull quay.io/YOUR_USERNAME/your-image-win:v1

# Use in make-vm.sh or other scripts
# Update the OCI_IMAGE_REPO variable to point to your published image
```

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
- Replace iptables with firewalld/nftables-aware rules where available.
- Improve Windows rsync: switch to push-on-change or periodic sync; exclude more locked paths.
- Add more poweshell scripts that execute flightctl binary commands and return a report of passed and failed
- Optional SMB path (documented) for non-RDP workflows.
- Parameterize CPU/RAM and RDP ports via env vars in `startup.sh`.
- Add cleanup script to remove VMs, networks, and temporary NVRAM files.
- Cache/prefetch Vagrant boxes in image build with version pins.

