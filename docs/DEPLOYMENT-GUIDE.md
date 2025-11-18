# Guide de déploiement Fleetman - Cluster kubeadm

## Vue d'ensemble

Ce guide vous permet de déployer l'application Fleetman sur votre cluster Kubernetes (1 master + 2 workers).

## Informations du cluster

- **Master** : `ssh master@192.168.56.10`
- **Worker1** : `ssh worker1@192.168.56.12`
- **Worker2** : `ssh worker2@192.168.56.11`

## Étapes de déploiement

### 1. Récupérer le kubeconfig

Depuis Windows PowerShell, exécutez :

```powershell
.\scripts\setup-kubeconfig.ps1 -MasterIP "192.168.56.10" -User "master"
```

Ce script va :
- Récupérer `/etc/kubernetes/admin.conf` depuis le master
- Le sauvegarder dans `$env:USERPROFILE\.kube\kubeconfig-kubeadm.yaml`
- Configurer kubectl pour utiliser ce fichier
- Vérifier la connexion au cluster

**Note** : Vous devrez saisir le mot de passe SSH du master.

### 2. Vérifier le cluster

```powershell
# Utiliser le kubeconfig
$env:KUBECONFIG = "$env:USERPROFILE\.kube\kubeconfig-kubeadm.yaml"

# Vérifier les nœuds
kubectl get nodes -o wide
```

Vous devriez voir 3 nœuds (1 master + 2 workers).

### 3. Déployer l'application

**Option A : Script automatique (recommandé)**

```powershell
.\scripts\deploy-fleetman.ps1 -KubeConfigPath "$env:USERPROFILE\.kube\kubeconfig-kubeadm.yaml"
```

**Option B : Déploiement manuel**

```powershell
# Définir le kubeconfig
$env:KUBECONFIG = "$env:USERPROFILE\.kube\kubeconfig-kubeadm.yaml"

# Appliquer les manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/fleetman-spring-config.yaml
kubectl apply -f k8s/fleetman-webapp-config.yaml
kubectl apply -f k8s/fleetman-mongodb.yaml
kubectl apply -f k8s/fleetman-queue.yaml
kubectl apply -f k8s/fleetman-position-simulator.yaml
kubectl apply -f k8s/fleetman-position-tracker.yaml
kubectl apply -f k8s/fleetman-api-gateway.yaml
kubectl apply -f k8s/fleetman-history-service.yaml
kubectl apply -f k8s/fleetman-positions-adapter.yaml
kubectl apply -f k8s/fleetman-web-app.yaml
```

### 4. Vérifier le déploiement

```powershell
# Voir l'état des pods
kubectl -n fleetman get pods -o wide

# Voir les services
kubectl -n fleetman get svc

# Voir les PVC (volumes persistants)
kubectl -n fleetman get pvc

# Voir les logs d'un pod
kubectl -n fleetman logs <pod-name>
```

### 5. Accéder à l'application

**Méthode 1 : Via NodePort (recommandé)**

L'application est accessible sur n'importe quel nœud worker via le port 30080 :

- `http://192.168.56.12:30080` (worker1)
- `http://192.168.56.11:30080` (worker2)

**Méthode 2 : Via port-forward**

```powershell
kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80
```

Puis ouvrir : `http://localhost:30080`

## Améliorations apportées

### 1. Ressources (CPU/Memory)

Tous les conteneurs ont maintenant des limites de ressources définies pour éviter les problèmes de mémoire :

- **position-tracker** : 512Mi-1Gi RAM, 250m-500m CPU
- **api-gateway** : 512Mi-1Gi RAM, 250m-500m CPU
- **queue** : 512Mi-1Gi RAM, 250m-500m CPU
- **mongodb** : 512Mi-1Gi RAM, 250m-500m CPU
- **position-simulator** : 256Mi-512Mi RAM, 100m-250m CPU
- **webapp** : 128Mi-256Mi RAM, 100m-200m CPU

### 2. Health Checks

Des probes de santé (readiness/liveness) ont été ajoutées pour :
- **position-tracker** : `/actuator/health`
- **api-gateway** : `/actuator/health`
- **webapp** : `/`

### 3. Configuration simplifiée

- Suppression des variables d'environnement en double
- Configuration centralisée via ConfigMaps
- Nettoyage des command/args inutiles

## Dépannage

### Les pods ne démarrent pas

```powershell
# Voir les événements
kubectl -n fleetman get events --sort-by='.lastTimestamp'

# Voir les logs d'un pod
kubectl -n fleetman logs <pod-name>

# Décrire un pod pour voir les erreurs
kubectl -n fleetman describe pod <pod-name>
```

### MongoDB ne démarre pas

```powershell
# Vérifier le PVC
kubectl -n fleetman get pvc

# Vérifier la StorageClass
kubectl get storageclass

# Si pas de StorageClass, créer une local-path
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
```

### Les positions ne s'affichent pas

```powershell
# Redémarrer la queue
kubectl -n fleetman rollout restart deploy/fleetman-queue

# Vérifier les logs du simulator
kubectl -n fleetman logs deploy/fleetman-position-simulator

# Vérifier les logs du tracker
kubectl -n fleetman logs deploy/fleetman-position-tracker
```

### Problème de connexion entre services

```powershell
# Tester depuis un pod
kubectl -n fleetman exec -it <pod-name> -- curl -sS http://fleetman-api-gateway:8080/actuator/health

# Vérifier les services DNS
kubectl -n fleetman exec -it <pod-name> -- nslookup fleetman-queue.fleetman.svc.cluster.local
```

## Suppression

Pour supprimer complètement l'application :

```powershell
kubectl delete -f k8s/ --namespace=fleetman
kubectl delete ns fleetman
```

## Architecture

```
┌─────────────────┐
│  fleetman-web-app│ (NodePort 30080)
│   (Nginx)       │
└────────┬────────┘
         │ /api/*
         ▼
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────────────┐
│fleetman-│ │fleetman-position- │
│api-     │ │    tracker        │
│gateway  │ └────────┬───────────┘
└─────────┘          │
                    │
    ┌───────────────┴───────────────┐
    │                               │
    ▼                               ▼
┌─────────┐              ┌──────────────────┐
│fleetman-│              │  fleetman-queue  │
│mongodb  │              │   (ActiveMQ)     │
└────┬────┘              └────────┬──────────┘
     │                           │ AMQP
     │                           ▼
     │                  ┌─────────────────┐
     │                  │fleetman-position-│
     │                  │   simulator      │
     │                  └─────────────────┘
     │
     ▼
┌─────────────────┐
│fleetman-history-│
│    service      │
└─────────────────┘
```

