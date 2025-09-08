#!/usr/bin/env bash
set -euo pipefail

OPENSHIFT_HOST="https://console-openshift-console.apps.ocp-edge-cluster-0.qe.lab.redhat.com"
OPENSHIFT_TOKEN="sha256~YatLrb4e3DT_sBTVha8_-R4D4SoeqvMCbBnueWXH8YY"
OPENSHIFT_API="https://api.ocp-edge-cluster-0.qe.lab.redhat.com:6443"
FLIGHTCTL_API="https://api.flightctl.apps.ocp-edge-cluster-0.qe.lab.redhat.com"
OCI_REGISTRY=quay.io
OCI_IMAGE_REPO=${OCI_REGISTRY}/sdelacru/$1
OCI_IMAGE_TAG=v1

if [ $# -eq 0 ]; then
      echo "Creates VM ready for flightctl usage and starts it"
      echo "Usage: make-vm.sh release"
      echo "  '<release>' is the release folder that we want to make ex:centos9"
      echo "Examples:"
      echo "  make-vm.sh                                       // displays this help text"
      echo "  make-vm.sh centos9                              // makes and start a centos9 flightctl ready VM"
      trap EXIT
      exit;
fi

# Login to OpenShift using oc, installing if missing
login_oc() {
  echo "Login to OpenShift"
  oc_path="$(find_oc || true)"
  if [ -n "$oc_path" ]; then
    "$oc_path" login --token="$OPENSHIFT_TOKEN" --server="$OPENSHIFT_API"
  else
    echo "Warning: oc binary not found installing and retrying"
    curl https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz | sudo tar xvz -C /usr/local/bin
    oc_path="$(find_oc || true)"
    "$oc_path" login --token="$OPENSHIFT_TOKEN" --server="$OPENSHIFT_API"
  fi
}

# Login to flightctl, installing the binary via COPR if missing
login_flightctl() {
  echo "Login to flightctl"
  flightctl_path="$(find_flightctl || true)"
  if [ -n "$flightctl_path" ]; then
    "$flightctl_path" login $FLIGHTCTL_API  --insecure-skip-tls-verify --token=$OPENSHIFT_TOKEN
  else
    echo "Warning: flightctl binary not found; installing and retrying..."
    sudo dnf -y install copr-cli
    sudo dnf copr enable -y @redhat-et/flightctl
    sudo dnf remove -y flightctl
    sudo dnf -y install flightctl
    flightctl_path="$(find_flightctl || true)"
    "$flightctl_path" login $FLIGHTCTL_API  --insecure-skip-tls-verify --token=$OPENSHIFT_TOKEN
  fi
}

find_oc() {
  if [ -n "${OC_BIN:-}" ] && [ -x "$OC_BIN" ]; then
    printf '%s\n' "$OC_BIN"
    return 0
  fi

  # 1) PATH lookup
  local cand
  cand="$(command -v oc 2>/dev/null || true)"
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    printf '%s\n' "$cand"
    return 0
  fi

  # 2) Common locations
  for p in ./oc ./bin/oc "$HOME/.local/bin/oc" /usr/local/bin/oc /usr/bin/oc; do
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

# Find a usable flightctl binary location
find_flightctl() {
  if [ -n "${FLIGHTCTL_BIN:-}" ] && [ -x "$FLIGHTCTL_BIN" ]; then
    printf '%s\n' "$FLIGHTCTL_BIN"
    return 0
  fi

  # 1) PATH lookup
  local cand
  cand="$(command -v flightctl 2>/dev/null || true)"
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    printf '%s\n' "$cand"
    return 0
  fi

  # 2) Common locations
  for p in ./flightctl ./bin/flightctl "$HOME/.local/bin/flightctl" /usr/local/bin/flightctl /usr/bin/flightctl; do
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

echo "Login to openshift and flightctl"
login_oc
login_flightctl

echo "Generate flightctl agent config"
cd $1
flightctl certificate request --signer=enrollment --expiration=365d --output=embedded > config.yaml
echo "Create requested image"
sudo podman build -t ${OCI_IMAGE_REPO}:${OCI_IMAGE_TAG} .
mkdir -p output

echo "Create qcow2 image"

mkdir output
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${PWD}/output":/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    ${OCI_IMAGE_REPO}:${OCI_IMAGE_TAG}

echo "Start VM"

export VMNAME=flightctl-$1
export VMRAM=4096
export VMCPUS=4
export VMDISK=/var/lib/libvirt/images/$VMNAME.qcow2
export VMWAIT=0

sudo cp ${PWD}/output/qcow2/disk.qcow2 $VMDISK
sudo qemu-img resize $VMDISK +20G
sudo chown libvirt:libvirt $VMDISK 2>/dev/null || true
sudo virt-install --name $VMNAME \
         --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
                                   --vcpus $VMCPUS \
                                   --memory $VMRAM \
                                   --import --disk $VMDISK,format=qcow2 \
                                   --os-variant fedora-eln  \
                                   --autoconsole text \
                                   --wait $VMWAIT \
                                   --transient || true
