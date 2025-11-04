# Mise en place d'un cluster Kubernetes (kubeadm) - 1 master + 2 workers

Ce document résume une procédure standard avec kubeadm sur des machines Ubuntu 22.04 (ou équivalent). Adaptez selon votre OS/hyperviseur/cloud.

## Prérequis systèmes (à exécuter sur tous les nœuds)
- 2 vCPU, 4+ Go RAM par nœud (min recommandé)
- Désactiver swap: `sudo swapoff -a` et supprimer toute entrée swap de `/etc/fstab`
- Horloge synchronisée (chrony/systemd-timesyncd)
- Ouvrir les ports réseau nécessaires (firewall), notamment:
  - Master: 6443 (API), 10250-10259, 2379-2380 etcd
  - Workers: 10250, VXLAN/overlay selon CNI
- Modules kernel réseau:

```bash
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

## Installer containerd + kubeadm/kubelet/kubectl (tous nœuds)

```bash
# containerd
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo systemctl enable --now containerd

# kubeadm/kubelet/kubectl
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Assurez-vous que `SystemdCgroup = true` dans `/etc/containerd/config.toml` (section `plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options`). Redémarrez containerd si modifié:

```bash
sudo systemctl restart containerd
```

## Initialiser le control-plane (master uniquement)

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

Configurer `kubectl` pour l'utilisateur courant:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Installer un plugin CNI (ex. Flannel):

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.5/Documentation/kube-flannel.yml
```

Note: si vous utilisez un autre CNI (Calico/Cilium), adaptez le `--pod-network-cidr` et la doc officielle.

## Joindre les workers
Sur le master, récupérez la commande join affichée par `kubeadm init`, sinon générez-la:

```bash
kubeadm token create --print-join-command
```

Exécutez-la sur chaque worker (avec `sudo`).

Vérifiez l'état du cluster:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## StorageClass par défaut
Sur environnement on‑prem, installez un provisioner (ex. local-path-provisioner) si aucune `StorageClass` par défaut n'est présente:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
```

## Déployer Fleetman
Suivez le guide `README-fleetman-deploy.md` à la racine du dépôt.

## Notes opérationnelles
- Ouvrir le NodePort 30080 sur les workers si un firewall est actif
- Pour accéder à l'app: `http://<IP_worker>:30080`
- En cas d'absence de positions, redémarrer `fleetman-queue` comme indiqué dans le README

