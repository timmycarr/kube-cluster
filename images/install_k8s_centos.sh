#!/bin/bash

# This is the default Kubernetes install script
# It assumes you can reach the kubernetes yum repo
# If that is *not* the case see the `install_k8s_centos_upload.sh`
# The "upload" script will require you retrieve the necessary binaries
#  for upload when building the AMI

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

sudo tee -a /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo yum install -y kubelet-1.9.7-0 kubeadm-1.9.7-0 kubectl-1.9.7-0
sudo systemctl enable kubelet

sudo curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl*

for pkg in $(ls /tmp/*_images.tar); do
    sudo docker load --input $pkg
done

