# Dépannage réseau - Master ne peut pas accéder à Internet

## Problème
Le master ne peut pas télécharger les images Flannel depuis Docker Hub.
Erreur : `dial tcp 18.235.105.159:443: connect: no route to host`

## Vérifications à faire

### 1. Vérifier l'accès Internet depuis le master

Connectez-vous au master :
```bash
ssh master@192.168.56.10
```

Testez la connexion Internet :
```bash
# Test ping
ping -c 3 8.8.8.8

# Test DNS
ping -c 3 google.com

# Test Docker Hub
ping -c 3 registry-1.docker.io
curl -I https://registry-1.docker.io
```

### 2. Vérifier la configuration réseau de la VM

**Dans Hyper-V Manager :**

1. **Vérifier NIC1 (vSwitch-Extern) :**
   - Clic droit sur la VM → Settings
   - Vérifier que la première carte réseau est connectée à `vSwitch-Extern`
   - Type : External (pontée sur votre carte réseau physique)

2. **Vérifier vSwitch-Extern :**
   - Dans Hyper-V Manager → Virtual Switch Manager
   - Vérifier que `vSwitch-Extern` est de type "External"
   - Vérifier qu'il est connecté à votre carte réseau Wi-Fi/Ethernet active

3. **Vérifier la configuration IP dans la VM :**
   ```bash
   # Depuis le master
   ip addr show
   # Vous devriez voir 2 interfaces :
   # - Une avec une IP DHCP (NIC1 - vSwitch-Extern)
   # - Une avec IP 192.168.56.10 (NIC2 - vSwitch-Interne)
   ```

### 3. Vérifier le routage

```bash
# Depuis le master
ip route show
# Vous devriez voir une route par défaut via NIC1
# Exemple : default via 192.168.x.x dev eth0
```

### 4. Vérifier que NIC1 obtient bien une IP via DHCP

```bash
# Depuis le master
sudo dhclient -v eth0  # ou le nom de votre interface NIC1
ip addr show eth0      # Vérifier qu'une IP a été obtenue
```

## Solutions

### Solution 1 : Forcer le renouvellement DHCP sur NIC1

```bash
# Depuis le master
sudo dhclient -r eth0  # Libérer l'IP actuelle
sudo dhclient -v eth0  # Renouveler l'IP
```

### Solution 2 : Vérifier la passerelle par défaut

```bash
# Depuis le master
ip route add default via <IP_PASSERELLE> dev eth0
# Remplacer <IP_PASSERELLE> par l'IP de votre routeur
```

### Solution 3 : Vérifier les DNS

```bash
# Depuis le master
cat /etc/resolv.conf
# Devrait contenir des serveurs DNS (ex: 8.8.8.8, 1.1.1.1)
```

### Solution 4 : Redémarrer le service réseau

```bash
# Depuis le master
sudo systemctl restart networking
# ou
sudo systemctl restart NetworkManager
```

### Solution 5 : Pré-télécharger les images depuis Windows

Si le master n'a vraiment pas accès Internet, vous pouvez télécharger les images depuis Windows et les transférer :

**Sur Windows (avec Docker Desktop ou accès Internet) :**
```powershell
# Télécharger les images Flannel
docker pull docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel1
docker pull docker.io/flannel/flannel:v0.25.5

# Sauvegarder les images
docker save docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel1 docker.io/flannel/flannel:v0.25.5 -o flannel-images.tar

# Transférer vers le master
scp flannel-images.tar master@192.168.56.10:~/
```

**Sur le master :**
```bash
# Charger les images dans containerd
sudo ctr -n k8s.io images import ~/flannel-images.tar

# Vérifier que les images sont chargées
sudo crictl images | grep flannel
```

## Vérification finale

Une fois l'accès Internet résolu :

```bash
# Depuis Windows
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get pods -n kube-flannel
# Le pod devrait passer de ImagePullBackOff à Running

kubectl get nodes
# Le nœud devrait passer de NotReady à Ready
```

## Commandes utiles

```bash
# Voir toutes les interfaces réseau
ip addr show

# Voir les routes
ip route show

# Tester la connectivité
ping -c 3 8.8.8.8
curl -I https://www.google.com

# Voir les logs du kubelet
sudo journalctl -u kubelet -f

# Voir les événements Kubernetes
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

