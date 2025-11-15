# Guide de configuration des VMs Kubernetes

Ce guide explique comment configurer les 3 VMs Hyper-V créées avec `Create-Fleetman-HyperV.ps1`.

## 📋 Prérequis

- 3 VMs créées (k8s-master, k8s-w1, k8s-w2)
- Ubuntu Server 22.04 installé sur chaque VM
- Accès SSH ou VMConnect pour chaque VM

## 🔧 Méthodes de copier/coller dans les VMs

### Méthode A : VMConnect (Presse-papiers)

1. **Côté Windows** : Copiez le contenu du script (Ctrl+C)
2. **Dans VMConnect** : Cliquez dans la fenêtre de la VM
3. **Menu** : Presse-papiers → "Taper le texte du presse-papiers"
4. Le texte sera "tapé" dans la console

**Pour un long script :**
```bash
cat > setup.sh
# (Menu Presse-papiers → Taper le texte…)
# Le contenu s'écrit ici...
# Quand c'est fini, appuyez sur Ctrl+D

chmod +x setup.sh
sudo bash setup.sh
```

### Méthode B : SSH (Recommandé)

**Sur chaque VM (une seule fois) :**
```bash
sudo apt update && sudo apt install -y openssh-server
ip -4 a | grep eth0
# Notez l'IP affichée (ex: 192.168.1.100)
```

**Sur Windows (PowerShell) :**
```powershell
# Se connecter
ssh <user>@<IP-VM>

# Copier un fichier
scp .\setup-k8s-master.sh <user>@<IP-master>:~/
scp .\setup-k8s-worker.sh <user>@<IP-worker>:~/
```

Dans Windows Terminal, utilisez **Ctrl+Shift+V** pour coller.

### Méthode C : Session améliorée (Optionnel)

1. Hyper-V Manager → Paramètres → Activer "Mode session améliorée"
2. Dans la VM :
   ```bash
   sudo apt update
   sudo apt install -y xorg xrdp ubuntu-desktop-minimal
   sudo systemctl enable --now xrdp
   ```
3. Reconnectez en Session améliorée → copier/coller natif

## 🚀 Configuration du Master

### Étape 1 : Transférer le script

**Option A - SSH (depuis Windows PowerShell) :**
```powershell
# Récupérer l'IP du master
Get-VMNetworkAdapter -VMName "k8s-master" | Select-Object -ExpandProperty IPAddresses

# Transférer le script
scp .\setup-k8s-master.sh <user>@<IP-master>:~/
```

**Option B - VMConnect :**
1. Ouvrez VMConnect pour k8s-master
2. Créez le fichier :
   ```bash
   cat > setup-k8s-master.sh
   # (Menu Presse-papiers → Taper le texte…)
   # Collez le contenu de setup-k8s-master.sh
   # Ctrl+D pour terminer
   ```

### Étape 2 : Exécuter le script

```bash
chmod +x setup-k8s-master.sh
sudo bash setup-k8s-master.sh
```

Le script va :
- ✅ Désactiver le swap
- ✅ Configurer les modules kernel
- ✅ Installer containerd
- ✅ Installer kubeadm/kubelet/kubectl
- ✅ Initialiser le cluster
- ✅ Installer Flannel CNI
- ✅ Configurer la StorageClass

### Étape 3 : Récupérer la commande join

```bash
kubeadm token create --print-join-command
```

**Copiez cette commande** - vous en aurez besoin pour les workers.

### Étape 4 : Vérifier l'état

```bash
kubectl get nodes
kubectl get pods -A
```

## 🔧 Configuration des Workers

### Étape 1 : Transférer le script

**Depuis Windows PowerShell :**
```powershell
# Pour k8s-w1
scp .\setup-k8s-worker.sh <user>@<IP-w1>:~/

# Pour k8s-w2
scp .\setup-k8s-worker.sh <user>@<IP-w2>:~/
```

### Étape 2 : Exécuter le script

**Sur k8s-w1 :**
```bash
chmod +x setup-k8s-worker.sh
sudo bash setup-k8s-worker.sh
```

Quand le script demande la commande join, **collez la commande obtenue sur le master**.

**Répétez pour k8s-w2.**

### Étape 3 : Vérifier sur le master

```bash
kubectl get nodes -o wide
```

Vous devriez voir 3 nœuds (1 master + 2 workers) en statut `Ready`.

## 📥 Copier le kubeconfig vers Windows

**Sur le master :**
```bash
# Notez votre IP
hostname -I
```

**Sur Windows (PowerShell) :**
```powershell
# Créer le répertoire .kube si nécessaire
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.kube"

# Copier le kubeconfig
scp <user>@<IP-master>:/home/<user>/.kube/config $env:USERPROFILE\.kube\config

# Tester
kubectl get nodes
```

## 🚢 Déployer Fleetman

**Depuis Windows (dans le répertoire du projet) :**
```powershell
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/fleetman-mongodb.yaml
kubectl apply -f k8s/fleetman-queue.yaml
kubectl apply -f k8s/fleetman-position-simulator.yaml
kubectl apply -f k8s/fleetman-position-tracker.yaml
kubectl apply -f k8s/fleetman-api-gateway.yaml
kubectl apply -f k8s/fleetman-webapp.yaml
kubectl apply -f k8s/fleetman-webapp-config.yaml
kubectl apply -f k8s/fleetman-spring-config.yaml

# Vérifier
kubectl get pods -n fleetman
kubectl get svc -n fleetman
```

## 🌐 Accéder à l'application

**Récupérer l'IP d'un worker :**
```powershell
Get-VMNetworkAdapter -VMName "k8s-w1" | Select-Object -ExpandProperty IPAddresses
```

**Ouvrir dans le navigateur :**
```
http://<IP-worker>:30080
```

## 🛠️ Commandes utiles

**Voir l'état des VMs :**
```powershell
Get-VM k8s-master,k8s-w1,k8s-w2 | Select-Object Name, State, CPUUsage, MemoryAssigned
```

**Démarrer toutes les VMs :**
```powershell
Get-VM k8s-master,k8s-w1,k8s-w2 | Start-VM
```

**Arrêter toutes les VMs :**
```powershell
Get-VM k8s-master,k8s-w1,k8s-w2 | Stop-VM
```

**Récupérer les IPs :**
```powershell
.\Get-VM-IPs.ps1
```

## ⚠️ Dépannage

**Si le swap n'est pas désactivé :**
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

**Si les modules kernel ne sont pas chargés :**
```bash
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
```

**Si containerd ne démarre pas :**
```bash
sudo systemctl status containerd
sudo systemctl restart containerd
```

**Si un worker ne joint pas le cluster :**
- Vérifiez que la commande join est correcte
- Vérifiez la connectivité réseau entre master et worker
- Vérifiez les ports firewall (6443, 10250, etc.)

## 📝 Notes

- Les scripts sont idempotents (peuvent être relancés)
- Le script master installe automatiquement Flannel et local-path-provisioner
- Le kubeconfig doit être copié manuellement vers Windows pour utiliser kubectl localement

