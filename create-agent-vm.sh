export VMNAME=flightctl-centos9
export VMRAM=4096
export VMCPUS=8
export VMDISK=/var/lib/libvirt/images/$VMNAME.qcow2
export VMWAIT=0

sudo cp centos9/output/qcow2/disk.qcow2 $VMDISK
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
