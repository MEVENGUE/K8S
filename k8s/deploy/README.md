# 🚀 Guide de déploiement Fleetman sur Kubernetes

Ce dossier contient les scripts de déploiement automatisé de l'application Fleetman sur un cluster Kubernetes (kubeadm).

## 📋 Prérequis

- Cluster Kubernetes fonctionnel (kubeadm 1 master + 2 workers)
- `kubectl` configuré et connecté au cluster
- Tous les fichiers YAML présents dans le dossier parent (`../`)

## ✅ Préparation (à faire une seule fois)

### 1. Se placer dans le dossier deploy

```bash
cd k8s/deploy
```

### 2. Donner les droits d'exécution aux scripts

```bash
chmod +x *.sh
```

## 🚀 Déploiement complet en étapes (mode manuel détaillé)

Pour un déploiement étape par étape (recommandé pour le rapport) :

### 🟦 Étape 1 — Création du namespace

```bash
./01-namespace.sh
```

**Ce que fait ce script :**
- Crée le namespace `fleetman`

---

### 🟦 Étape 2 — Déploiement des services core (MongoDB + ActiveMQ)

```bash
./02-core-services.sh
```

**Ce que fait ce script :**
- Déploie MongoDB (StatefulSet + PersistentVolume)
- Déploie ActiveMQ (Queue)
- Attend que MongoDB soit READY (timeout: 300s)
- Attend que ActiveMQ soit READY (timeout: 180s)

**Durée estimée :** 2-3 minutes

---

### 🟦 Étape 3 — Déploiement des microservices applicatifs

```bash
./03-app-services.sh
```

**Ce que fait ce script :**
- Déploie le ConfigMap pour la WebApp Nginx
- Déploie Position Simulator
- Déploie Position Tracker
- Déploie Positions Adapter
- Déploie API Gateway
- Déploie History Service
- Déploie Web App
- Attend le readiness de tous les services

**Durée estimée :** 3-5 minutes (l'API Gateway prend 2-3 minutes à démarrer)

---

### 🟦 Étape 4 — Vérification automatique du déploiement

```bash
./04-verify.sh
```

**Ce que fait ce script :**
- Vérifie l'état de tous les pods
- Teste la résolution DNS Kubernetes (Position Tracker, API Gateway, MongoDB)
- Vérifie les services
- Vérifie le NodePort de la Web App
- Teste la connectivité interne

---

## 🎉 Déploiement complet en une seule commande (mode automatisé)

Pour déployer tout d'un coup :

```bash
./deploy-all.sh
```

**Ce script exécute automatiquement :**
1. `01-namespace.sh`
2. `02-core-services.sh`
3. `03-app-services.sh`
4. `04-verify.sh`

**Durée totale estimée :** 5-8 minutes

---

## 📌 Ordre recommandé pour le rapport officiel

Dans votre rendu PDF du mini-projet, documentez ainsi :

### 1. Préparation

```bash
cd k8s/deploy
chmod +x *.sh
```

### 2. Déploiement du namespace

```bash
./01-namespace.sh
```

**Résultat attendu :**
```
➡ Création du namespace fleetman...
namespace/fleetman created
✔ Namespace créé.
```

### 3. Déploiement des services essentiels (MongoDB + Queue)

```bash
./02-core-services.sh
```

**Résultat attendu :**
```
➡ Déploiement MongoDB (StatefulSet + PV)...
statefulset.apps/fleetman-mongodb created
service/fleetman-mongodb created
➡ Déploiement ActiveMQ...
deployment.apps/fleetman-queue created
service/fleetman-queue created
➡ Attente de MongoDB...
pod/fleetman-mongodb-0 condition met
➡ Attente de ActiveMQ...
deployment.apps/fleetman-queue condition met
✔ Core services prêts.
```

### 4. Déploiement des microservices

```bash
./03-app-services.sh
```

**Résultat attendu :**
```
➡ Déploiement des ConfigMaps...
configmap/fleetman-webapp-nginx created
➡ Déploiement Position Simulator...
deployment.apps/fleetman-position-simulator created
...
➡ Attente du readiness de tous les services...
deployment.apps/fleetman-position-simulator condition met
...
✔ Tous les services applicatifs sont prêts.
```

### 5. Vérification automatique

```bash
./04-verify.sh
```

**Résultat attendu :**
```
➡ Vérification de l'état des pods...
NAME                                          READY   STATUS    RESTARTS   AGE
...
➡ Vérification DNS Kubernetes...
...
✔ Tests terminés.
```

### (Optionnel) Déploiement complet en un clic

```bash
./deploy-all.sh
```

---

## 🔍 Vérification manuelle

### Vérifier l'état des pods

```bash
kubectl get pods -n fleetman
```

### Vérifier les services

```bash
kubectl get svc -n fleetman
```

### Vérifier les logs d'un service

```bash
kubectl logs -n fleetman deployment/fleetman-api-gateway
```

### Accéder à l'application

Une fois le déploiement terminé, l'application est accessible sur :

**http://localhost:30080**

---

## 🛠️ Dépannage

### Si un pod est en erreur

```bash
# Voir les détails du pod
kubectl describe pod <nom-pod> -n fleetman

# Voir les logs
kubectl logs <nom-pod> -n fleetman
```

### Si un service ne démarre pas

```bash
# Vérifier les événements
kubectl get events -n fleetman --sort-by='.lastTimestamp'

# Redémarrer un deployment
kubectl rollout restart deployment/<nom-deployment> -n fleetman
```

### Réinitialiser complètement

```bash
# Supprimer tout le namespace (ATTENTION : supprime toutes les données)
kubectl delete namespace fleetman

# Puis relancer le déploiement
./deploy-all.sh
```

---

## 📝 Notes importantes

- **MongoDB** : Utilise un StatefulSet avec PersistentVolume. Les données persistent même après redémarrage.
- **DNS Kubernetes** : Tous les services utilisent des DNS Kubernetes (`*.svc.cluster.local`) et non des IPs hardcodées.
- **NodePort** : La Web App est accessible via le NodePort `30080` sur tous les nœuds du cluster.
- **Profil Spring** : Tous les microservices Spring Boot utilisent le profil `production-microservice`.

---

## ✅ Checklist de déploiement

- [ ] Cluster Kubernetes fonctionnel
- [ ] `kubectl` configuré
- [ ] Tous les fichiers YAML présents dans `../`
- [ ] Scripts avec droits d'exécution (`chmod +x *.sh`)
- [ ] Namespace créé
- [ ] MongoDB et ActiveMQ déployés et prêts
- [ ] Tous les microservices déployés et prêts
- [ ] Application accessible sur http://localhost:30080

---

## 📝 Notes importantes sur la configuration actuelle

- **ActiveMQ** : Service ClusterIP avec DNS Kubernetes (`tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)
- **MongoDB** : Utilise le FQDN complet (`fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`)
- **Nginx** : Configuration avec timeouts (60s) et routage intelligent vers différents backends
- **History Service** : Service Python Flask pour l'historique des véhicules
- **Images** : Toutes les images utilisent la version `1.1.0` (sauf `fleetman-history-service` qui utilise `python:3.9-slim`)

**Dernière mise à jour :** 2025-11-18

