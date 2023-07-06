#!/bin/bash
# Scripts for install a Kubernetes cluster with 3 Nodes in Ubuntu 18.04 Bionic Beaver

IsMaster=0

if [ $# -gt 0 ]
then
    if [ "$1" == "-n" ] || [ "$1" == "--node" ]
    then
    	if [ $# -eq 5 ]
    	then
    		IsMaster=0
			NAME=$2
			MASTERIP=$3
			TOKEN=$4
			HASH=$5
    	else
    		echo "You need to set the Node Name, MASTERIP and pass the token master and the discovery-token-ca-cert-hash getting from the master node"
    		echo "Example: ./install.sh -n kubernetes-node01 172.31.26.148 v320m9.x4lb0hayszu6n9fo sha256:3c32be01539a52f642bb664b1a85dbca619bb82459bb24514f0c203fa786623b"
    		exit 0
    	fi
    elif [ "$1" == "-m" ] || [ "$1" == "--master" ]
    then
    	IsMaster=1
    elif [ "$1" == "-h" ] || [ "$1" == "--help" ]
    then
    	echo "** Instructions **"
    	echo "1 - Install the master: ./install.sh -m||--master"
    	echo "2 - You need to set the Node Name, MASTERIP and pass the token master and the discovery-token-ca-cert-hash getting from the master node"
    	echo "3 - ./install.sh -n kubernetes-node01 192.168.1.1 v320m9.x4lb0hayszu6n9fo sha256:3c32be01539a52f642bb664b1a85dbca619bb82459bb24514f0c203fa786623b"
    	exit 0
    else
    	echo "install.sh [-n|--node or -m|--master]"
    	exit 0
    fi
else
	echo "install.sh [-n|--node + NODE-NAME + TOKEN or -m|--master]"
	exit 0
fi

#Get the Docker gpg key:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

#Add the Docker repository:
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

#Get the Kubernetes gpg key:
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

#Add the Kubernetes repository:
cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

#Update your packages:
sudo apt-get update

#Install Docker, kubelet, kubeadm, and kubectl, last version:
sudo apt-get install -y docker-ce kubelet kubeadm kubectl

#Hold them at the current version:
sudo apt-mark hold docker-ce kubelet kubeadm kubectl

#Add the iptables rule to sysctl.conf:
echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf

#Enable iptables immediately:
sudo sysctl -p

#Initialize the cluster (run only on the master):
if [ $IsMaster -eq 1 ]
then
	sudo swapoff -a
	sudo hostnamectl set-hostname kubernetes-master
	sudo kubeadm init --pod-network-cidr=10.244.0.0/16
    #Set up local kubeconfig:
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    #Apply Flannel CNI network overlay:
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

else
    #Join the worker nodes to the cluster:
	sudo hostnamectl set-hostname $NAME
	sudo kubeadm join $MASTERIP:6443 --token $TOKEN --discovery-token-ca-cert-hash $HASH
fi

