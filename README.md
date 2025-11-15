# Déploiement de l'application Trucks sur Kubernetes

Ce projet contient les manifests Kubernetes pour déployer une application microservices distribuée "Trucks" qui simule et suit la position de véhicules en temps réel.

## 📋 Table des matières

1. [Architecture de l'application](#architecture-de-lapplication)
2. [Composants et fichiers](#composants-et-fichiers)
3. [Relations entre les composants](#relations-entre-les-composants)
4. [Déploiement](#déploiement)
5. [Explication détaillée des fichiers](#explication-détaillée-des-fichiers)
6. [Flux de données](#flux-de-données)
7. [Accès à l'application](#accès-à-lapplication)
8. [Dépannage](#dépannage)

---

## 🏗️ Architecture de l'application

L'application Trucks est composée de 6 microservices qui communiquent entre eux :

```
┌─────────────────┐
│  trucks-web-app │ (Interface utilisateur - NodePort 30081)
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐
│trucks-api-gateway│ (Point d'entrée API - ClusterIP)
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐
│trucks-position-│ (API REST + Consommateur - ClusterIP)
│    tracker      │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────────┐
│trucks-  │ │trucks-queue  │ (ActiveMQ - ClusterIP)
│mongodb  │ │              │
└─────────┘ └──────┬───────┘
                   │ AMQP
                   ▼
         ┌─────────────────┐
         │trucks-position-  │ (Producteur de messages)
         │   simulator      │
         └─────────────────┘
```

---

## 📦 Composants et fichiers

### Fichiers principaux de déploiement

| Fichier | Type | Fonction |
|---------|------|----------|
| `namespace.yaml` | Namespace | Crée l'espace de noms `trucks` |
| `trucks-mongodb.yaml` | StatefulSet + Service | Base de données MongoDB avec persistance |
| `trucks-queue.yaml` | Deployment + Service | Broker de messages ActiveMQ |
| `trucks-position-simulator.yaml` | Deployment + Service | Simulateur de positions de véhicules |
| `trucks-position-tracker.yaml` | Deployment + Service | Tracker qui consomme les messages et expose une API |
| `trucks-api-gateway.yaml` | Deployment + Service | Passerelle API (point d'entrée backend) |
| `trucks-web-app.yaml` | Deployment + Service | Application web frontend |
| `trucks-webapp-config.yaml` | ConfigMap | Configuration Nginx pour la webapp (proxy vers API Gateway) |
| `trucks-ingress.yaml` | Ingress | Expose l'application via Ingress (optionnel, alternative au NodePort) |

---

## 🔗 Relations entre les composants

### 1. **trucks-mongodb** (Base de données)
- **Type** : StatefulSet (pour persistance)
- **Service** : Headless Service (`clusterIP: None`)
- **Utilisé par** :
  - `trucks-position-tracker` (stocke les positions)
  - `trucks-api-gateway` (lit les données)

### 2. **trucks-queue** (Message Broker)
- **Type** : Deployment
- **Service** : ClusterIP (ports 61616 AMQP, 8161 UI)
- **Utilisé par** :
  - `trucks-position-simulator` (envoie des messages)
  - `trucks-position-tracker` (consomme les messages)

### 3. **trucks-position-simulator** (Producteur)
- **Type** : Deployment
- **Dépend de** : `trucks-queue` (via `ACTIVEMQ_URL`)
- **Fonction** : Génère des positions de véhicules et les envoie à la queue

### 4. **trucks-position-tracker** (Consommateur + API)
- **Type** : Deployment (2 réplicas)
- **Dépend de** :
  - `trucks-queue` (consomme les messages)
  - `trucks-mongodb` (stocke les positions)
- **Utilisé par** : `trucks-api-gateway`

### 5. **trucks-api-gateway** (Passerelle API)
- **Type** : Deployment (2 réplicas)
- **Dépend de** :
  - `trucks-position-tracker` (appelle l'API)
  - `trucks-mongodb` (accès direct à la base)
- **Utilisé par** : `trucks-web-app`

### 6. **trucks-web-app** (Frontend)
- **Type** : Deployment (2 réplicas)
- **Service** : NodePort (port 30081)
- **Dépend de** : `trucks-api-gateway` (via `API_GATEWAY_URL`)

---

## 🚀 Déploiement

### Prérequis
- Un cluster Kubernetes (1 master + 2 workers minimum)
- `kubectl` configuré vers ce cluster
- Une `StorageClass` par défaut fonctionnelle pour provisionner les PVC

### Ordre de déploiement (IMPORTANT)

Les composants doivent être déployés dans cet ordre pour respecter les dépendances :

```bash
# 1. Créer le namespace
kubectl apply -f k8s/namespace.yaml

# 2. Déployer MongoDB (base de données - doit être prêt en premier)
kubectl apply -f k8s/trucks-mongodb.yaml

# 3. Déployer la queue ActiveMQ (nécessaire pour les messages)
kubectl apply -f k8s/trucks-queue.yaml

# 4. Déployer le ConfigMap Nginx (nécessaire pour la webapp)
kubectl apply -f k8s/trucks-webapp-config.yaml

# 5. Déployer le simulateur (peut démarrer en parallèle)
kubectl apply -f k8s/trucks-position-simulator.yaml

# 6. Déployer le tracker (dépend de MongoDB et Queue)
kubectl apply -f k8s/trucks-position-tracker.yaml

# 7. Déployer l'API Gateway (dépend du tracker)
kubectl apply -f k8s/trucks-api-gateway.yaml

# 8. Déployer l'application web (dépend de l'API Gateway et du ConfigMap)
kubectl apply -f k8s/trucks-web-app.yaml

# Optionnel : Déployer l'Ingress (alternative au NodePort, nécessite un contrôleur Ingress)
# kubectl apply -f k8s/trucks-ingress.yaml
```

### Vérification du déploiement

```bash
# Vérifier tous les pods
kubectl get pods -n trucks

# Vérifier tous les services
kubectl get svc -n trucks

# Vérifier les déploiements
kubectl get deployments -n trucks

# Vérifier MongoDB (StatefulSet)
kubectl get statefulset -n trucks

# Vérifier les volumes persistants
kubectl get pvc -n trucks

# Vue d'ensemble
kubectl get all -n trucks
```

---

## 📖 Explication détaillée des fichiers

### 1. `namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: trucks
```

**Fonction** :
- Crée un namespace isolé nommé `trucks` pour toutes les ressources de l'application
- Permet d'organiser et d'isoler les ressources Kubernetes

**Pourquoi c'est important** :
- Évite les conflits de noms avec d'autres applications
- Permet de gérer les permissions et quotas par namespace
- Facilite la suppression de toute l'application d'un coup

---

### 2. `trucks-mongodb.yaml`

**Contient** : Service Headless + StatefulSet

#### Service Headless

```yaml
apiVersion: v1
kind: Service
metadata:
  name: trucks-mongodb
  namespace: trucks
spec:
  clusterIP: None  # Service Headless
  selector:
    app: trucks-mongodb
  ports:
    - name: mongo
      port: 27017
      targetPort: 27017
```

**Fonction** :
- Service Headless (`clusterIP: None`) : permet un accès direct aux pods MongoDB
- Expose le port 27017 (port standard MongoDB)
- Chaque pod MongoDB a un nom DNS stable : `trucks-mongodb-0.trucks-mongodb.trucks.svc.cluster.local`

**Pourquoi Headless Service** :
- Permet la découverte directe des pods pour la réplication MongoDB
- Nécessaire pour les StatefulSets qui ont besoin d'identités stables

#### StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: trucks-mongodb
spec:
  serviceName: trucks-mongodb  # Référence au service Headless
  replicas: 1
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
```

**Fonction** :
- **StatefulSet** : Gère les pods avec identité stable (nom : `trucks-mongodb-0`)
- **volumeClaimTemplates** : Crée automatiquement un PVC (`data-trucks-mongodb-0`) de 5Gi pour chaque pod
- Le volume est monté dans `/data/db` (répertoire par défaut de MongoDB)

**Pourquoi StatefulSet et pas Deployment** :
- **Persistance** : Les données MongoDB doivent survivre aux redémarrages
- **Identité stable** : Le pod garde toujours le même nom et le même volume
- **Ordre de déploiement** : Important pour la réplication MongoDB

**Liens avec autres composants** :
- Utilisé par `trucks-position-tracker` via `SPRING_DATA_MONGODB_URI=mongodb://trucks-mongodb:27017/trucks`
- Utilisé par `trucks-api-gateway` via `SPRING_DATA_MONGODB_URI=mongodb://trucks-mongodb:27017/trucks`

---

### 3. `trucks-queue.yaml`

**Contient** : Deployment + Service ClusterIP

#### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trucks-queue
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/queue:1.1.0
          ports:
            - containerPort: 61616  # Port AMQP (messages)
            - containerPort: 8161   # Port UI (console web)
```

**Fonction** :
- Déploie ActiveMQ (broker de messages)
- Port 61616 : Pour les messages AMQP (utilisé par simulator et tracker)
- Port 8161 : Interface web de gestion ActiveMQ

#### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: trucks-queue
spec:
  type: ClusterIP
  ports:
    - name: amqp
      port: 61616
      targetPort: amqp
    - name: ui
      port: 8161
      targetPort: ui
```

**Fonction** :
- Expose ActiveMQ dans le cluster
- Les autres pods peuvent accéder via `trucks-queue:61616` (résolution DNS automatique)

**Liens avec autres composants** :
- Utilisé par `trucks-position-simulator` via `ACTIVEMQ_URL=tcp://trucks-queue:61616`
- Utilisé par `trucks-position-tracker` via `ACTIVEMQ_URL=tcp://trucks-queue:61616`

---

### 4. `trucks-position-simulator.yaml`

**Contient** : Deployment + Service

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trucks-position-simulator
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/position-simulator:1.1.0
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: production-microservice
            - name: ACTIVEMQ_URL
              value: tcp://trucks-queue:61616
            - name: VEHICLE_COUNT
              value: "12"
            - name: MESSAGE_FREQUENCY_MS
              value: "500"
```

**Fonction** :
- **Producteur de messages** : Génère des positions de véhicules simulées
- Envoie les messages à ActiveMQ via `trucks-queue:61616`
- **VEHICLE_COUNT** : Nombre de véhicules à simuler (12)
- **MESSAGE_FREQUENCY_MS** : Fréquence d'envoi (toutes les 500ms)

**Flux** :
1. Génère des positions GPS aléatoires pour 12 véhicules
2. Envoie chaque position à la queue ActiveMQ
3. Répète toutes les 500ms

**Liens avec autres composants** :
- **Dépend de** : `trucks-queue` (doit être déployé avant)
- **Produit pour** : `trucks-position-tracker` (consomme les messages)

---

### 5. `trucks-position-tracker.yaml`

**Contient** : Deployment + Service ClusterIP

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trucks-position-tracker
spec:
  replicas: 2  # Haute disponibilité
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/position-tracker:1.1.0
          env:
            - name: ACTIVEMQ_URL
              value: tcp://trucks-queue:61616
            - name: SPRING_DATA_MONGODB_URI
              value: mongodb://trucks-mongodb:27017/trucks
          readinessProbe:
            tcpSocket:
              port: 8080
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 40
            periodSeconds: 10
```

**Fonction** :
- **Consommateur** : Lit les messages de la queue ActiveMQ
- **API REST** : Expose une API HTTP sur le port 8080 pour récupérer les positions
- **Stockage** : Sauvegarde les positions dans MongoDB
- **2 réplicas** : Pour la haute disponibilité et la charge

**Probes** :
- **readinessProbe** : Vérifie que le pod est prêt à recevoir du trafic (toutes les 5s)
- **livenessProbe** : Vérifie que le pod est toujours vivant (toutes les 10s, après 40s de démarrage)

**Flux** :
1. Consomme les messages de `trucks-queue`
2. Stocke chaque position dans MongoDB (`trucks` database)
3. Expose une API REST pour récupérer les positions stockées

**Liens avec autres composants** :
- **Dépend de** :
  - `trucks-queue` (consomme les messages)
  - `trucks-mongodb` (stocke les données)
- **Utilisé par** : `trucks-api-gateway` (appelle l'API REST)

---

### 6. `trucks-api-gateway.yaml`

**Contient** : Deployment + Service ClusterIP

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trucks-api-gateway
spec:
  replicas: 2  # Haute disponibilité
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/api-gateway:1.1.0
          env:
            - name: FLEETMAN_POSITION_TRACKER_URL
              value: http://trucks-position-tracker.trucks.svc.cluster.local:8080
            - name: SPRING_DATA_MONGODB_URI
              value: mongodb://trucks-mongodb:27017/trucks
```

**Fonction** :
- **Passerelle API** : Point d'entrée unique pour le backend
- **Aggrégation** : Combine les données de plusieurs sources
- **2 réplicas** : Pour la haute disponibilité

**URL complète du tracker** :
- `http://trucks-position-tracker.trucks.svc.cluster.local:8080`
- Format DNS Kubernetes : `<service>.<namespace>.svc.cluster.local:<port>`
- Permet l'accès même si le service est dans un autre namespace

**Liens avec autres composants** :
- **Dépend de** :
  - `trucks-position-tracker` (appelle l'API)
  - `trucks-mongodb` (accès direct pour certaines requêtes)
- **Utilisé par** : `trucks-web-app` (appelle l'API Gateway)

---

### 7. `trucks-web-app.yaml`

**Contient** : Deployment + Service NodePort

#### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trucks-web-app
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/web-app:1.1.0
          env:
            - name: API_GATEWAY_URL
              value: /api
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
      volumes:
        - name: nginx-config
          configMap:
            name: trucks-webapp-nginx
```

**Fonction** :
- **Frontend** : Application web (Nginx + HTML/JS)
- **2 réplicas** : Pour la haute disponibilité
- **ConfigMap** : Utilise `trucks-webapp-nginx` pour la configuration Nginx
- **API_GATEWAY_URL** : Chemin relatif `/api` pour appeler l'API Gateway

**Note** : Le ConfigMap `trucks-webapp-nginx` doit être créé séparément (non inclus dans ce fichier).

#### Service NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: trucks-web-app
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 30081
```

**Fonction** :
- **NodePort** : Expose l'application à l'extérieur du cluster
- **Port 30081** : Accessible depuis n'importe quel nœud du cluster
- **Port 80** : Port interne du service

**Liens avec autres composants** :
- **Dépend de** : 
  - `trucks-api-gateway` (appelle `/api` qui pointe vers l'API Gateway)
  - `trucks-webapp-nginx` ConfigMap (configuration Nginx)

---

### 8. `trucks-webapp-config.yaml`

**Contient** : ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: trucks-webapp-nginx
  namespace: trucks
data:
  nginx.conf: |
    # Configuration Nginx complète
    upstream api_gateway {
      server trucks-api-gateway.trucks.svc.cluster.local:8080;
    }
    # Proxy /api/ vers l'API Gateway
    location /api/ {
      proxy_pass http://api_gateway/;
    }
```

**Fonction** :
- **ConfigMap** : Stocke la configuration Nginx pour la webapp
- **Proxy reverse** : Configure Nginx pour rediriger les requêtes `/api/` vers `trucks-api-gateway`
- **Upstream** : Définit le serveur backend (API Gateway) avec son URL DNS complète
- **WebSocket** : Support des connexions WebSocket pour les mises à jour en temps réel

**Pourquoi c'est nécessaire** :
- La webapp (`trucks-web-app.yaml`) monte ce ConfigMap dans `/etc/nginx/nginx.conf`
- Sans ce ConfigMap, Nginx ne saurait pas où rediriger les requêtes API
- Permet de séparer la configuration du code de l'application

**Liens avec autres composants** :
- **Utilisé par** : `trucks-web-app` (monté comme volume dans le pod)

---

### 9. `trucks-ingress.yaml` (Optionnel)

**Contient** : Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: trucks-ingress
  namespace: trucks
spec:
  rules:
    - host: trucks.local
      http:
        paths:
          - path: /api
            backend:
              service:
                name: trucks-api-gateway
          - path: /
            backend:
              service:
                name: trucks-web-app
```

**Fonction** :
- **Ingress** : Expose l'application via un contrôleur Ingress (alternative au NodePort)
- **Routage** : Route `/api` vers l'API Gateway et `/` vers la webapp
- **Host** : Accessible via `trucks.local` (nécessite configuration DNS ou `/etc/hosts`)

**Quand l'utiliser** :
- Si vous avez un contrôleur Ingress installé (ex: NGINX Ingress Controller)
- Pour exposer l'application via un nom de domaine au lieu d'une IP:port
- Pour gérer le TLS/HTTPS automatiquement

**Note** : Si vous utilisez NodePort (port 30081), vous n'avez pas besoin de cet Ingress.

**Liens avec autres composants** :
- **Utilise** : `trucks-api-gateway` et `trucks-web-app` (services backend)

---

## 🔄 Flux de données

### Flux complet de bout en bout

```
1. trucks-position-simulator
   └─> Génère des positions GPS (12 véhicules, toutes les 500ms)
       └─> Envoie à trucks-queue (ActiveMQ) via AMQP

2. trucks-queue (ActiveMQ)
   └─> Stocke les messages dans une queue
       └─> Distribue aux consommateurs

3. trucks-position-tracker
   └─> Consomme les messages de trucks-queue
       ├─> Stocke dans trucks-mongodb (base de données)
       └─> Expose une API REST sur le port 8080

4. trucks-api-gateway
   └─> Appelle trucks-position-tracker (API REST)
       ├─> Peut aussi lire directement trucks-mongodb
       └─> Agrège et expose une API unifiée

5. trucks-web-app
   └─> Appelle trucks-api-gateway via /api
       └─> Affiche les positions sur une carte web

6. Utilisateur
   └─> Accède à http://<node-ip>:30081
       └─> Voit la carte avec les positions en temps réel
```

### Séquence de démarrage

```
1. MongoDB démarre (StatefulSet)
   └─> Crée le PVC et monte le volume
   └─> MongoDB écoute sur le port 27017

2. Queue démarre (Deployment)
   └─> ActiveMQ démarre
   └─> Écoute sur les ports 61616 et 8161

3. Simulator démarre (Deployment)
   └─> Se connecte à trucks-queue:61616
   └─> Commence à envoyer des messages

4. Tracker démarre (Deployment)
   └─> Se connecte à trucks-queue:61616 (consomme)
   └─> Se connecte à trucks-mongodb:27017 (stocke)
   └─> Démarre l'API REST sur le port 8080
   └─> readinessProbe vérifie que le port 8080 répond

5. API Gateway démarre (Deployment)
   └─> Se connecte à trucks-position-tracker (HTTP)
   └─> Se connecte à trucks-mongodb (optionnel)
   └─> readinessProbe vérifie que le port 8080 répond

6. Web App démarre (Deployment)
   └─> Charge la config Nginx depuis ConfigMap
   └─> readinessProbe vérifie que le port 80 répond
   └─> Accessible via NodePort 30081
```

---

## 🌐 Accès à l'application

### Accès externe (NodePort)

```bash
# Trouver l'IP d'un nœud worker
kubectl get nodes -o wide

# Accéder à l'application
http://<IP_WORKER>:30081
```

Exemple :
- `http://192.168.56.12:30081` (worker1)
- `http://192.168.56.11:30081` (worker2)

### Accès local (Port Forward)

```bash
kubectl -n trucks port-forward svc/trucks-web-app 30081:80
```

Puis ouvrir : `http://localhost:30081`

### Accès à la console ActiveMQ

```bash
# Port-forward vers la console ActiveMQ
kubectl -n trucks port-forward svc/trucks-queue 8161:8161
```

Puis ouvrir : `http://localhost:8161` (admin/admin par défaut)

---

## 🔧 Dépannage

### Vérifier l'état des pods

```bash
# Voir tous les pods
kubectl get pods -n trucks

# Voir les détails d'un pod en erreur
kubectl describe pod <nom-du-pod> -n trucks

# Voir les logs d'un pod
kubectl logs <nom-du-pod> -n trucks

# Suivre les logs en temps réel
kubectl logs -f <nom-du-pod> -n trucks
```

### Vérifier les services et endpoints

```bash
# Voir tous les services
kubectl get svc -n trucks

# Voir les endpoints (pods associés aux services)
kubectl get endpoints -n trucks

# Détails d'un service
kubectl describe svc <nom-service> -n trucks
```

### Vérifier MongoDB

```bash
# Voir le StatefulSet
kubectl get statefulset trucks-mongodb -n trucks

# Voir le pod MongoDB
kubectl get pods -n trucks | grep mongodb

# Voir les logs MongoDB
kubectl logs trucks-mongodb-0 -n trucks

# Vérifier le PVC
kubectl get pvc -n trucks

# Détails du PVC
kubectl describe pvc data-trucks-mongodb-0 -n trucks
```

### Vérifier la connectivité entre services

```bash
# Tester depuis un pod tracker vers l'API Gateway
kubectl exec -n trucks -it <pod-tracker> -- \
  curl -sS http://trucks-api-gateway:8080/actuator/health

# Tester depuis un pod tracker vers MongoDB
kubectl exec -n trucks -it <pod-tracker> -- \
  nc -zv trucks-mongodb 27017

# Tester depuis un pod tracker vers la queue
kubectl exec -n trucks -it <pod-tracker> -- \
  nc -zv trucks-queue 61616
```

### Redémarrer un composant

```bash
# Redémarrer un déploiement
kubectl rollout restart deploy/trucks-queue -n trucks

# Redémarrer un StatefulSet
kubectl rollout restart statefulset/trucks-mongodb -n trucks

# Supprimer un pod (sera recréé automatiquement)
kubectl delete pod <nom-du-pod> -n trucks
```

### Problèmes courants

1. **Pods en CrashLoopBackOff**
   - Vérifier les logs : `kubectl logs <pod> -n trucks`
   - Vérifier que les dépendances sont prêtes (MongoDB, Queue)

2. **Pods en ImagePullBackOff**
   - Vérifier que les images Docker existent
   - Vérifier les permissions du registry

3. **Service sans endpoints**
   - Vérifier que les pods ont les bons labels
   - Vérifier que les pods sont READY (readinessProbe)

4. **MongoDB ne démarre pas**
   - Vérifier que le PVC est créé : `kubectl get pvc -n trucks`
   - Vérifier la StorageClass : `kubectl get storageclass`

---

## 🗑️ Suppression

### Supprimer l'application complète

```bash
# Supprimer tous les déploiements
kubectl delete -f k8s/trucks-*.yaml --namespace=trucks

# Supprimer le namespace (supprime tout)
kubectl delete ns trucks
```

### Supprimer uniquement les ressources (garder le namespace)

```bash
# Supprimer chaque composant individuellement
kubectl delete -f k8s/trucks-mongodb.yaml
kubectl delete -f k8s/trucks-queue.yaml
kubectl delete -f k8s/trucks-position-simulator.yaml
kubectl delete -f k8s/trucks-position-tracker.yaml
kubectl delete -f k8s/trucks-api-gateway.yaml
kubectl delete -f k8s/trucks-web-app.yaml
```

**Note** : Les PVC (volumes persistants) ne sont pas supprimés automatiquement. Pour les supprimer :

```bash
kubectl delete pvc -n trucks --all
```

---

## 📊 Résumé des ressources

| Ressource | Nombre | Type |
|-----------|--------|------|
| **Namespace** | 1 | `trucks` |
| **StatefulSet** | 1 | `trucks-mongodb` (1 replica) |
| **Deployments** | 5 | Queue (1), Simulator (1), Tracker (2), API Gateway (2), Web App (2) |
| **Services** | 6 | 5 ClusterIP + 1 NodePort |
| **PVC** | 1 | `data-trucks-mongodb-0` (5Gi) |
| **Total Pods** | 9 | 1 MongoDB + 1 Queue + 1 Simulator + 2 Tracker + 2 API Gateway + 2 Web App |

---

## 🎯 Points clés à retenir

1. **Ordre de déploiement** : MongoDB → Queue → Simulator → Tracker → API Gateway → Web App
2. **StatefulSet pour MongoDB** : Nécessaire pour la persistance des données
3. **Service Headless pour MongoDB** : Permet l'accès direct aux pods
4. **NodePort pour Web App** : Seul service accessible de l'extérieur
5. **Probes** : Readiness et Liveness probes assurent la disponibilité
6. **DNS Kubernetes** : Les services se trouvent automatiquement via DNS (`<service>.<namespace>.svc.cluster.local`)

---

## 📚 Ressources supplémentaires

- [Documentation Kubernetes - StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Documentation Kubernetes - Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Documentation Kubernetes - Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
