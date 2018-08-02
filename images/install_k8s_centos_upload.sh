#!/bin/bash

# The default Kubernetes install script is `install_k8s_centos.sh`
# Use this version if you are unable to reach the kubernetes yum repo
# If you use this install script you will need to retrieve the necessary binaries
#  (in kubernetes-node-linux-amd64.tar.gz) for upload when building the AMI
# the Kubernetes CHANGELOGs for links to node binaries
# e.g. https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.9.md#node-binaries-2

sudo yum clean all
sudo yum update -y
sudo yum clean all

# disable SELinux
sudo mv /tmp/selinux_config /etc/selinux/config

# disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker

cd /tmp; tar xvf /tmp/kubernetes-node-linux-amd64.tar.gz
sudo mv /tmp/kubernetes/node/bin/kubelet /usr/bin/
sudo mv /tmp/kubernetes/node/bin/kubectl /usr/bin/
sudo mv /tmp/kubernetes/node/bin/kubeadm /usr/bin/
rm /tmp/kubernetes-node-linux-amd64.tar.gz
rm -rf /tmp/kubernetes
sudo mv /tmp/kubelet.service /lib/systemd/system/
sudo mkdir /etc/systemd/system/kubelet.service.d/
sudo systemctl enable kubelet

sudo curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl*

for pkg in $(ls /tmp/*_images.tar); do
    sudo docker load --input $pkg
done

