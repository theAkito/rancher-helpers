#!/bin/bash
# See LICENSE.
# Copyright (C) 2019 Akito
# Based on https://github.com/rancher/rancher/issues/19882#issuecomment-501056386

## Cleans up Rancher *entirely*.
## After running this script you are able to
## set up Rancher entirely from scratch
## without any complaints about remains
## from the previous installation.

# Removes ALL containers.
docker rm -f $(sudo docker ps -aq);
# Removes ALL volumes.
docker volume rm $(sudo docker volume ls -q);
# Removes all Rancher and Kubernetes related folders.
rm -fr /etc/ceph \
       /etc/cni \
       /etc/kubernetes \
       /opt/cni \
       /opt/rke \
       /run/secrets/kubernetes.io \
       /run/calico \
       /run/flannel \
       /var/lib/calico \
       /var/lib/etcd \
       /var/lib/cni \
       /var/lib/kubelet \
       /var/lib/rancher/rke/log \
       /var/log/containers \
       /var/log/pods \
       /var/run/calico
# Unmounts all Rancher and Kubernetes related virtual devices and volumes.
for mount in \
  $(mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }') \
  /var/lib/kubelet /var/lib/rancher; do umount $mount; done
# Removes metadata database.
rm -f /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db
# Removes Firewall entries related to Rancher or Kubernetes.
IPTABLES="/sbin/iptables"
cat /proc/net/ip_tables_names | while read table; do
  $IPTABLES -t $table -L -n | while read c chain rest; do
      if test "X$c" = "XChain" ; then
        $IPTABLES -t $table -F $chain
      fi
  done
  $IPTABLES -t $table -X
done
# Removes Rancher installation.
rm -fr /opt/rancher
# Restarts services, to apply previous removals.
sudo systemctl restart containerd
sudo systemctl stop docker
# Needs a pause, because else it complains about "too quick" restarts.
sleep 10
sudo systemctl start docker
