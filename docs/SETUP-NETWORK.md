# Guide de configuration du réseau Kubernetes

## État actuel
✅ Master accessible : 192.168.56.10  
✅ Workers accessibles : 192.168.56.12, 192.168.56.11  
✅ Cluster Kubernetes créé  
✅ Application Fleetman déployée  
⚠️ CNI réseau non installé (nœud NotReady)  
⚠️ Workers non ajoutés au cluster  

## Étapes à suivre

### 1. Installer le CNI Flannel

**Depuis Windows PowerShell :**
```powershell
ssh master@192.168.56.10
# Entrez le mot de passe du master

# Une fois connecté au master, exécutez :
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.5/Documentation/kube-flannel.yml

# Attendez 30 secondes, puis vérifiez :
kubectl get pods -n kube-flannel
kubectl get nodes
```

**Ou directement depuis Windows (si SSH sans mot de passe configuré) :**
```powershell
ssh master@192.168.56.10 "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.5/Documentation/kube-flannel.yml"
```

### 2. Vérifier que Flannel démarre

Attendez 30-60 secondes, puis depuis Windows :
```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get pods -n kube-flannel
kubectl get nodes
```

Le nœud master devrait passer de `NotReady` à `Ready`.

### 3. Récupérer la commande join pour les workers

**Depuis le master :**
```bash
kubeadm token create --print-join-command
```

Cela affichera une commande comme :
```bash
kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 4. Ajouter worker1 au cluster

**Depuis Windows PowerShell :**
```powershell
ssh worker1@192.168.56.12
# Entrez le mot de passe

# Exécutez la commande join récupérée à l'étape 3 avec sudo :
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 5. Ajouter worker2 au cluster

**Depuis Windows PowerShell :**
```powershell
ssh worker2@192.168.56.11
# Entrez le mot de passe

# Exécutez la même commande join avec sudo :
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 6. Vérifier que les workers sont ajoutés

**Depuis Windows PowerShell :**
```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get nodes -o wide
```

Vous devriez voir 3 nœuds :
- k8s-master (Ready)
- worker1 (Ready)
- worker2 (Ready)

### 7. Vérifier que les pods Fleetman démarrent

```powershell
kubectl -n fleetman get pods -o wide
```

Les pods devraient maintenant passer de `Pending` à `Running` et être répartis sur les workers.

### 8. Accéder à l'application

Une fois tous les pods en `Running`, accédez à l'application via :

**NodePort (depuis n'importe quel worker) :**
- http://192.168.56.12:30080
- http://192.168.56.11:30080

**Ou via port-forward :**
```powershell
kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80
```
Puis ouvrir : http://localhost:30080

## Dépannage

### Si Flannel ne démarre pas

Vérifiez l'accès Internet depuis le master :
```bash
ping -c 3 8.8.8.8
ping -c 3 registry-1.docker.io
```

Si pas d'accès Internet, vérifiez que NIC1 (vSwitch-Extern) est bien configurée avec DHCP.

### Si les workers ne peuvent pas joindre

Vérifiez que :
- Les workers peuvent ping le master : `ping 192.168.56.10`
- Le port 6443 est ouvert : `telnet 192.168.56.10 6443`
- Les workers ont les mêmes prérequis que le master (containerd, kubeadm, etc.)

### Si les pods restent en Pending

Vérifiez les événements :
```powershell
kubectl -n fleetman describe pod <pod-name>
kubectl get events -n fleetman --sort-by='.lastTimestamp'
```

## Commandes utiles

```powershell
# Voir tous les pods
kubectl get pods -A

# Voir les services
kubectl -n fleetman get svc

# Voir les logs d'un pod
kubectl -n fleetman logs <pod-name>

# Redémarrer un déploiement
kubectl -n fleetman rollout restart deploy/<deployment-name>

# Voir l'état du cluster
kubectl cluster-info
```

