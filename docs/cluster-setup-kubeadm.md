# Mise en place d'un cluster Kubernetes (kubeadm) - 1 master + 2 workers

Ce document résume une procédure standard avec kubeadm sur des machines Ubuntu 22.04 (ou équivalent). Adaptez selon votre OS/hyperviseur/cloud.

> Utilisation depuis Windows (PowerShell) – résumé rapide
> - Installez kubectl: `choco install kubernetes-cli -y` (ou `winget install Kubernetes.kubectl`)
> - Activez le client OpenSSH Windows pour utiliser `ssh`/`scp` vers vos VM Linux
> - Exécutez les commandes Linux ci‑dessous par SSH depuis votre PC Windows
> - Ouvrez la webapp: `Start-Process "http://<IP_worker>:30080"`
> - Fichier hosts si besoin d'un alias: `C:\\Windows\\System32\\drivers\\etc\\hosts`

## Création des VMs Hyper-V (Windows 10/11 Pro/Enterprise)

Si vous utilisez Hyper-V pour créer votre cluster kubeadm, utilisez le script PowerShell fourni :

### Prérequis
- Windows Pro/Enterprise avec Hyper-V activé
- ISO Ubuntu Server 22.04 téléchargée
- PowerShell exécuté en tant qu'administrateur

### Utilisation du script

1. **Personnalisez les variables** dans `Create-Fleetman-HyperV.ps1` :
   - `$IsoPath` : Chemin vers votre ISO Ubuntu 22.04 (ex: `C:\ISO\ubuntu-22.04.5-live-server-amd64.iso`)
   - `$SwitchName` : Nom du vSwitch externe (par défaut: `vSwitch-External`)
   - `$ExternalAdapterName` : Nom de votre adaptateur réseau (`Wi-Fi` ou `Ethernet`)
   - `$VmRoot` : Répertoire de stockage des VMs (ex: `C:\HyperV\Fleetman`)

2. **Vérifiez votre adaptateur réseau** :
   ```powershell
   Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object Name
   ```

3. **Exécutez le script** :
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\Create-Fleetman-HyperV.ps1
   ```

Le script crée automatiquement :
- **1 VM master** (`k8s-master`) : 2 CPU, 4-6 Go RAM, 30 Go disque
- **2 VMs workers** (`k8s-w1`, `k8s-w2`) : 2 CPU, 3-5 Go RAM, 30 Go disque

Toutes les VMs sont configurées avec :
- Génération 2 (UEFI)
- Secure Boot pour Linux (Microsoft UEFI CA)
- vSwitch externe (pontage réseau)
- Disques dynamiques
- Mémoire dynamique avec limites

### Récupérer les IPs des VMs

Après l'installation d'Ubuntu sur chaque VM, récupérez les adresses IP :

```powershell
# Utilisez le script fourni
.\Get-VM-IPs.ps1

# Ou manuellement
Get-VMNetworkAdapter -VMName "k8s-master" | Select-Object -ExpandProperty IPAddresses
Get-VMNetworkAdapter -VMName "k8s-w1" | Select-Object -ExpandProperty IPAddresses
Get-VMNetworkAdapter -VMName "k8s-w2" | Select-Object -ExpandProperty IPAddresses
```

### Commandes utiles pour gérer les VMs

```powershell
# Démarrer toutes les VMs
Get-VM k8s-master,k8s-w1,k8s-w2 | Start-VM

# Arrêter toutes les VMs
Get-VM k8s-master,k8s-w1,k8s-w2 | Stop-VM

# Voir l'état des VMs
Get-VM k8s-master,k8s-w1,k8s-w2 | Select-Object Name, State, CPUUsage, MemoryAssigned
```

### Notes importantes

- **vSwitch externe** : Les VMs obtiennent des IPs réelles via DHCP de votre réseau local
- **Performances** : Ajustez CPU/RAM dans le script si vous avez plus de ressources
- **ISO** : Assurez-vous que le chemin vers l'ISO est correct
- **Installation Ubuntu** : Installez Ubuntu Server 22.04 sur chaque VM avec DHCP activé

Après la création des VMs et l'installation d'Ubuntu, suivez les instructions ci-dessous pour configurer le cluster kubeadm.

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
sudo kubeadm init --pod-network-cidr=10.244.x.x/xx
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

## Tests locaux avec kind (Windows) - Optionnel mais recommandé

> ⚠️ **Important** : kind sert uniquement à **tester/développer** vos manifests Kubernetes en local avant le déploiement sur le cluster kubeadm réel. Le cluster noté doit être **kubeadm (1 master + 2 workers)** comme exigé par l'énoncé.

### Prérequis pour kind
- **Docker Desktop** installé et démarré (mode Linux containers)
- **kubectl** installé (voir section Windows ci-dessus)
- **kind** installé : `choco install kind -y` ou `winget install Kubernetes.kind`

### Créer le cluster kind (3 nœuds)

Le fichier `kind-config.yaml` à la racine du dépôt configure 1 control-plane + 2 workers :

```powershell
# Créer le cluster
kind create cluster --config=kind-config.yaml

# Vérifier
kubectl cluster-info
kubectl get nodes
```

Vous devriez voir 3 nœuds (1 control-plane + 2 workers) en statut `Ready`.

### Configurer le stockage (PVC MongoDB)

kind n'a pas de StorageClass par défaut. Installez `local-path-provisioner` :

```powershell
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
```

La PVC MongoDB se liera automatiquement (plus de statut `Pending`).

### Déployer Fleetman sur kind

```powershell
# Depuis la racine du dépôt
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/fleetman-mongodb.yaml
kubectl apply -f k8s/fleetman-queue.yaml
kubectl apply -f k8s/fleetman-position-simulator.yaml
kubectl apply -f k8s/fleetman-position-tracker.yaml
kubectl apply -f k8s/fleetman-api-gateway.yaml
kubectl apply -f k8s/fleetman-webapp.yaml
kubectl apply -f k8s/fleetman-webapp-config.yaml

# Vérifier
kubectl get pods -n fleetman
kubectl get svc -n fleetman
```

### Accéder à l'application

Le port 30080 est mappé depuis le control-plane vers votre PC Windows :

```powershell
Start-Process "http://localhost:30080"
```

### Tester la tolérance à la panne

Simulez la panne d'un worker :

```powershell
# Lister les conteneurs kind
docker ps --format "table {{.ID}}\t{{.Names}}" | findstr kind

# Arrêter un worker (ex: fleetman-worker2)
docker stop <container_name_of_worker2>

# Vérifier que les pods se répartissent sur les nœuds restants
kubectl get pods -n fleetman -o wide
```

Si vos Deployments ont `replicas: 1` et sont bien répartis, l'application reste disponible.

### Nettoyer le cluster kind

```powershell
kind delete cluster --name fleetman
```

### Astuces et pièges courants

- **Port 30080 déjà utilisé** : modifiez `hostPort` dans `kind-config.yaml` (ex. 30090) et l'URL correspondante.
- **Images privées** : si vous buildez localement, utilisez `kind load docker-image <image>` après `docker build`.
- **Volumes** : avec `local-path-provisioner`, pas besoin de créer des PV manuellement.
- **DNS interne** : gardez les noms de Services `fleetman-*` (pas d'IP en dur dans vos manifests).

### Dans votre rendu

- Expliquez que **kind** a servi de **banc de test local** (multi-nœuds, port mappé, storage par local-path).
- Montrez **1 capture** de `kubectl get nodes` (3 nœuds Ready) + **1 capture** du navigateur `http://localhost:30080`.
- **Rappelez** que le **cluster noté** est bien **kubeadm 1M/2W** (documenté dans la section principale), et que **kind ne remplace pas** cette exigence — il **accélère le développement**.

## Déployer Fleetman sur le cluster kubeadm

Suivez le guide `README-fleetman-deploy.md` à la racine du dépôt.

## Notes opérationnelles
- Ouvrir le NodePort 30080 sur les workers si un firewall est actif
- Pour accéder à l'app: `http://<IP_worker>:30080`
- En cas d'absence de positions, redémarrer `fleetman-queue` comme indiqué dans le README

## Annexes – Windows 10/11 (PowerShell)

### Installer kubectl
```
choco install kubernetes-cli -y
# ou
winget install Kubernetes.kubectl
kubectl version --client
```

### Se connecter aux nœuds Linux
```
ssh ubuntu@<ip-master>
ssh ubuntu@<ip-worker1>
ssh ubuntu@<ip-worker2>
```

### Copier un fichier avec scp
```
scp .\kube-flannel.yml ubuntu@<ip-master>:/home/ubuntu/
```

### Utiliser le kubeconfig localement
Sur le master Linux après `kubeadm init`:
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
Puis sur Windows (PowerShell):
```
scp ubuntu@<ip-master>:/home/ubuntu/.kube/config $env:USERPROFILE\.kube\config
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get nodes
```

### Accéder à la webapp depuis Windows
```
Start-Process "http://<IP_worker>:30080"
```

### Dépannage rapide (PowerShell)
```
kubectl -n fleetman get pods,svc
kubectl -n fleetman rollout restart deployment/fleetman-queue
Invoke-WebRequest -UseBasicParsing http://<IP_worker>:30080/api/vehicles
Invoke-WebRequest -UseBasicParsing "http://<IP_worker>:30080/api/history/City%20Truck"
```

