# Guide pour résoudre les erreurs lors de l'ajout des workers

## Problèmes identifiés

1. ❌ `kubeadm token create` exécuté depuis worker1 au lieu du master
2. ❌ Erreur "user is not running as root" même avec sudo

## Solution

### Étape 1 : Récupérer la commande join depuis le MASTER

**Depuis Windows PowerShell :**
```powershell
ssh master@192.168.56.10 "kubeadm token create --print-join-command"
```

**Ou connectez-vous au master :**
```bash
ssh master@192.168.56.10
kubeadm token create --print-join-command
```

Cela affichera une commande comme :
```bash
kubeadm join 192.168.56.10:6443 --token <nouveau-token> --discovery-token-ca-cert-hash sha256:3f20ba33f10daefdc773a4c324e28404a7c31acabbd03aad5d01b02c22b6a488
```

### Étape 2 : Nettoyer worker1 (si nécessaire)

**Depuis Windows PowerShell :**
```powershell
ssh worker1@192.168.56.12 "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/etcd /etc/kubernetes ~/.kube && sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X"
```

### Étape 3 : Résoudre l'erreur "user is not running as root"

L'erreur indique que sudo ne fonctionne pas correctement. Essayez :

**Option A : Vérifier que l'utilisateur est dans le groupe sudo**
```bash
ssh worker1@192.168.56.12
groups
# Doit contenir "sudo"
```

Si pas dans sudo :
```bash
# Depuis le master ou avec accès root
sudo usermod -aG sudo worker1
```

**Option B : Utiliser directement root (si disponible)**
```bash
ssh root@192.168.56.12
# Puis exécuter la commande join sans sudo
```

**Option C : Vérifier la configuration sudo**
```bash
ssh worker1@192.168.56.12
sudo -v
# Si ça échoue, il y a un problème de configuration sudo
```

### Étape 4 : Exécuter la commande join sur worker1

**Une fois nettoyé et avec sudo fonctionnel :**
```bash
ssh worker1@192.168.56.12
sudo kubeadm join 192.168.56.10:6443 --token <token-du-master> --discovery-token-ca-cert-hash sha256:3f20ba33f10daefdc773a4c324e28404a7c31acabbd03aad5d01b02c22b6a488
```

**Si sudo ne fonctionne toujours pas, essayez avec --ignore-preflight-errors :**
```bash
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:3f20ba33f10daefdc773a4c324e28404a7c31acabbd03aad5d01b02c22b6a488 --ignore-preflight-errors=IsPrivilegedUser
```

### Étape 5 : Répéter pour worker2

```powershell
# Nettoyer worker2
ssh worker2@192.168.56.11 "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/etcd /etc/kubernetes ~/.kube && sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X"

# Joindre le cluster (utiliser le même token que pour worker1)
ssh worker2@192.168.56.11
sudo kubeadm join 192.168.56.10:6443 --token <même-token> --discovery-token-ca-cert-hash sha256:3f20ba33f10daefdc773a4c324e28404a7c31acabbd03aad5d01b02c22b6a488
```

### Étape 6 : Vérifier depuis Windows

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get nodes -o wide
```

Vous devriez voir 3 nœuds :
- k8s-master (Ready)
- k8s-worker1 (Ready) 
- k8s-worker2 (Ready)

## Commandes rapides

**Récupérer le token depuis le master :**
```powershell
ssh master@192.168.56.10 "kubeadm token create --print-join-command"
```

**Nettoyer et joindre worker1 (une seule commande) :**
```powershell
$token = ssh master@192.168.56.10 "kubeadm token create --print-join-command" | Select-String "kubeadm join"
ssh worker1@192.168.56.12 "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/etcd /etc/kubernetes ~/.kube && sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X && sudo $token"
```

## Dépannage supplémentaire

### Si "user is not running as root" persiste

Vérifiez que vous êtes bien root avec sudo :
```bash
whoami
sudo whoami
# Doit afficher "root"
```

Si ça ne fonctionne pas, vérifiez /etc/sudoers :
```bash
sudo visudo
# Vérifier que worker1 a les droits sudo
```

### Si le worker ne peut pas joindre

Vérifiez la connectivité :
```bash
# Depuis worker1
ping 192.168.56.10
telnet 192.168.56.10 6443
```

Vérifiez que les services sont actifs :
```bash
sudo systemctl status containerd
sudo systemctl status kubelet
```

