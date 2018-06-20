#!/bin/bash

# wait for permanent hostname
HOSTNAME_PRE="ip-172"
while [ "$HOSTNAME_PRE" != "ip-10" ]; do
    echo "permanent hostname not yet available"
    sleep 10
    HOSTNAME_PRE=$(hostname | cut -c1-5)
done
HOSTNAME=$(hostname)

PRIVATE_IP=""
while [ "$PRIVATE_IP" == "" ]; do
    echo "private IP not yet available"
    sleep 10
    PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')
done

# shut up broken DNS warnings
if ! grep -q $host /etc/hosts; then
  echo "fixing broken /etc/hosts"
  cat <<EOF | sudo dd oflag=append conv=notrunc of=/etc/hosts >/dev/null 2>&1
# added by bootstrap_etcd0.sh `date`
$PRIVATE_IP $HOSTNAME
EOF
fi

API_LB_EP=0
ETCD_TLS=0
ETCD0_IP=0
ETCD1_IP=0
ETCD2_IP=0
PROXY_EP=0
MASTER_IPS=0
VPC_CIDR=0
IMAGE_REPO=0
API_DNS=0
INSTALL_COMPLETE=0

# ensure iptables are used correctly
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# reset any existing iptables rules
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -F
sudo iptables -X

# proxy vars for docker
while [ $PROXY_EP -eq 0 ]; do
    if [ -f /tmp/proxy_ep ]; then
        PROXY_EP=$(cat /tmp/proxy_ep)
    else
        echo "proxy endpoint not yet available"
        sleep 10
    fi
done

# master node IP addresses
while [ $MASTER_IPS -eq 0 ]; do
    if [ -f /tmp/master_ips ]; then
        MASTER_IPS=$(cat /tmp/master_ips)
    else
        echo "master ips not yet available"
        sleep 10
    fi
done

# VPC CIDR
while [ $VPC_CIDR -eq 0 ]; do
    if [ -f /tmp/vpc_cidr ]; then
        VPC_CIDR=$(cat /tmp/vpc_cidr)
    else
        echo "vpc cidr not yet available"
        sleep 10
    fi
done

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$PROXY_EP:3128/" "HTTPS_PROXY=http://$PROXY_EP:3128/" "NO_PROXY=docker-pek.cnqr-cn.com,$HOSTNAME,localhost,$MASTER_IPS,127.0.0.1,169.254.169.254,192.168.0.0/16,$VPC_CIDR"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# image repo to pull images from
while [ $IMAGE_REPO -eq 0 ]; do
    if [ -f /tmp/image_repo ]; then
        IMAGE_REPO=$(cat /tmp/image_repo)
    else
        echo "image repo not yet available"
        sleep 10
    fi
done

# get the ELB domain name for the API server
while [ $API_LB_EP -eq 0 ]; do
    if [ -f /tmp/api_lb_ep ]; then
        API_LB_EP=$(cat /tmp/api_lb_ep)
    else
        echo "API load balancer endpoint not yet available"
        sleep 10
    fi
done

# change pause image repo
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$PROXY_EP:3128/" "HTTPS_PROXY=http://$PROXY_EP:3128/" "NO_PROXY=docker-pek.cnqr-cn.com,$HOSTNAME,localhost,.default.svc.cluster.local,.svc.cluster.local,.cluster.local,.cn-north-1.compute.internal,$API_LB_EP,127.0.0.1,169.254.169.254,192.168.0.0/16,10.96.0.0/12,$VPC_CIDR"
Environment="KUBELET_NODE_ROLE=--node-labels=node-role.kubernetes.io/master="
Environment="KUBELET_INFRA_IMAGE=--pod-infra-container-image=${IMAGE_REPO}/pause-amd64:3.0"
Environment="KUBELET_CGROUPS=--cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
Environment="KUBELET_CLOUD_PROVIDER=--cloud-provider=aws"
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_CADVISOR_ARGS=--cadvisor-port=0"
Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_NODE_ROLE \$KUBELET_INFRA_IMAGE \$KUBELET_CGROUPS \$KUBELET_CLOUD_PROVIDER \$KUBELET_KUBECONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_DNS_ARGS \$KUBELET_AUTHZ_ARGS \$KUBELET_CADVISOR_ARGS \$KUBELET_CERTIFICATE_ARGS \$KUBELET_EXTRA_ARGS
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# get etcd TLS assets so API server can connect
sudo mkdir -p /etc/kubernetes/pki/etcd

while [ $ETCD_TLS -eq 0 ]; do
    if [ -f /tmp/etcd_tls.tar.gz ]; then
        (cd /tmp; tar xvf /tmp/etcd_tls.tar.gz)
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca-key.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/client.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/client-key.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca-config.json /etc/kubernetes/pki/etcd/
        ETCD_TLS=1
    else
        echo "etcd tls assets not yet available"
        sleep 10
    fi
done

# get the IPs for the etcd members
while [ $ETCD0_IP -eq 0 ]; do
    if [ -f /tmp/etcd0_ip ]; then
        ETCD0_IP=$(cat /tmp/etcd0_ip)
    else
        echo "etcd0 IP not yet available"
        sleep 10
    fi
done

while [ $ETCD1_IP -eq 0 ]; do
    if [ -f /tmp/etcd1_ip ]; then
        ETCD1_IP=$(cat /tmp/etcd1_ip)
    else
        echo "etcd1 IP not yet available"
        sleep 10
    fi
done

while [ $ETCD2_IP -eq 0 ]; do
    if [ -f /tmp/etcd2_ip ]; then
        ETCD2_IP=$(cat /tmp/etcd2_ip)
    else
        echo "etcd2 IP not yet available"
        sleep 10
    fi
done

# API DNS name
while [ $API_DNS -eq 0 ]; do
    if [ -f /tmp/api_dns ]; then
        API_DNS=$(cat /tmp/api_dns)
    else
        echo "API DNS not yet available"
        sleep 10
    fi
done

# generate kubeadm config
cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: ${PRIVATE_IP}
etcd:
  endpoints:
  - https://${ETCD0_IP}:2379
  - https://${ETCD1_IP}:2379
  - https://${ETCD2_IP}:2379
  caFile: /etc/kubernetes/pki/etcd/ca.pem
  certFile: /etc/kubernetes/pki/etcd/client.pem
  keyFile: /etc/kubernetes/pki/etcd/client-key.pem
networking:
  podSubnet: 192.168.0.0/16
apiServerCertSANs:
- ${API_LB_EP}
- ${API_DNS}
apiServerExtraArgs:
  endpoint-reconciler-type: "lease"
  external-hostname: "${HOSTNAME}.cn-north-1.compute.internal"
controllerManagerExtraArgs:
  configure-cloud-routes: "false"
kubernetesVersion: "1.9.7"
cloudProvider: "aws"
imageRepository: $IMAGE_REPO
nodeName: "${HOSTNAME}.cn-north-1.compute.internal"
EOF

# initialize
HTTP_PROXY="http://$PROXY_EP:3128" \
    HTTPS_PROXY="http://$PROXY_EP:3128" \
    NO_PROXY="docker-pek.cnqr-cn.com,$HOSTNAME,localhost,.default.svc.cluster.local,.svc.cluster.local,.cluster.local,.cn-north-1.compute.internal,$API_LB_EP,127.0.0.1,169.254.169.254,192.168.0.0/16,10.96.0.0/12,$VPC_CIDR" \
    sudo -E bash -c 'kubeadm init --config=/tmp/kubeadm-config.yaml'

# tar up the K8s TLS assets to distribute to other masters
sudo tar cvf /tmp/k8s_tls.tar.gz /etc/kubernetes/pki

# put the kubeconfig in a convenient location
mkdir -p /home/ec2-user/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
sudo chown -R ec2-user:ec2-user /home/ec2-user/.kube

# deploy networking
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico-rbac-kdd.yaml
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico.yaml

# get a join command ready for distribution to workers
sudo kubeadm token create --description "Token created and used by kube-cluster bootstrapper" --print-join-command > /tmp/join
sudo chown ec2-user:ec2-user /tmp/join

# clean
while [ $INSTALL_COMPLETE -eq 0 ]; do
    if [ -f /tmp/install_complete ]; then
        sudo rm -rf /tmp/etc
        sudo rm /tmp/api_lb_ep \
            /tmp/etcd0_ip \
            /tmp/etcd1_ip \
            /tmp/etcd2_ip \
            /tmp/etcd_tls.tar.gz \
            /tmp/image_repo \
            /tmp/join \
            /tmp/k8s_tls.tar.gz \
            /tmp/kubeadm-config.yaml \
            /tmp/proxy_ep
        INSTALL_COMPLETE=1
    else
        echo "cluster installation not yet complete"
        sleep 10
    fi
done

echo "bootstrap complete"
exit 0

