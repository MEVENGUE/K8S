# Déploiement de l'application Fleetman sur Kubernetes

Ce projet contient les manifests Kubernetes pour déployer une application microservices distribuée "Fleetman" qui simule et suit la position de véhicules en temps réel.

<img width="1596" height="871" alt="image" src="https://github.com/user-attachments/assets/1683ab63-b1e3-4071-8f76-91f59e3637f8" />


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

L'application Fleetman est composée de 8 microservices qui communiquent entre eux :

```
┌─────────────────┐
│  fleetman-web-app │ (Interface utilisateur - NodePort 30080)
└────────┬────────┘
         │ HTTP /api/*
         ▼
┌─────────────────┐
│fleetman-api-gateway│ (Point d'entrée API - ClusterIP)
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐
│fleetman-position-│ (API REST + Consommateur - ClusterIP)
│    tracker      │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────────┐
│fleetman-  │ │fleetman-queue  │ (ActiveMQ - ClusterIP)
│mongodb  │ │              │
└────┬────┘ └──────┬───────┘
     │             │ AMQP
     │             ▼
     │    ┌─────────────────┐
     │    │fleetman-position-  │ (Producteur de messages)
     │    │   simulator      │
     │    └─────────────────┘
     │
     ▼
┌─────────────────┐
│fleetman-history-│ (Service historique - ClusterIP)
│    service      │
└─────────────────┘

┌─────────────────┐
│fleetman-positions│ (Adapter Nginx - ClusterIP)
│    adapter      │
└─────────────────┘
```

---

## 📦 Composants et fichiers

### Utiliser les outils et technologies suivants :

<img width="674" height="420" alt="image" src="https://github.com/user-attachments/assets/f6453799-3b88-4d1e-abd4-d328a94078ee" />

### Fichiers principaux de déploiement

| Fichier | Type | Fonction |
|---------|------|----------|
| `namespace.yaml` | Namespace | Crée l'espace de noms `fleetman` |
| `fleetman-mongodb.yaml` | StatefulSet + Service | Base de données MongoDB avec persistance |
| `fleetman-queue.yaml` | Deployment + Service | Broker de messages ActiveMQ |
| `fleetman-position-simulator.yaml` | Deployment + Service | Simulateur de positions de véhicules |
| `fleetman-position-tracker.yaml` | Deployment + Service | Tracker qui consomme les messages et expose une API |
| `fleetman-api-gateway.yaml` | Deployment + Service | Passerelle API (point d'entrée backend) |
| `fleetman-history-service.yaml` | Deployment + Service | Service Python Flask pour l'historique des véhicules |
| `fleetman-positions-adapter.yaml` | Deployment + Service + ConfigMap | Adapter Nginx pour le Position Tracker |
| `fleetman-web-app.yaml` | Deployment + Service | Application web frontend |
| `fleetman-webapp-config.yaml` | ConfigMap | Configuration Nginx pour la webapp (routage vers services backend) |

---

## 🔗 Relations entre les composants

### 1. **fleetman-mongodb** (Base de données)
- **Type** : StatefulSet (pour persistance)
- **Service** : Headless Service (`clusterIP: None`)
- **Utilisé par** :
  - `fleetman-position-tracker` (stocke les positions)
  - `fleetman-api-gateway` (lit les données)

### 2. **fleetman-queue** (Message Broker)
- **Type** : Deployment (2 réplicas)
- **Service** : ClusterIP (ports 61616 OpenWire, 8161 UI)
- **Image** : `supinfo4kube/queue:1.1.0` (ActiveMQ 5.17.3)
- **Utilisé par** :
  - `fleetman-position-simulator` (envoie des messages via `tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)
  - `fleetman-position-tracker` (consomme les messages via `tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)

### 3. **fleetman-position-simulator** (Producteur)
- **Type** : Deployment (1 replica)
- **Image** : `supinfo4kube/position-simulator:1.1.0`
- **Dépend de** : `fleetman-queue` (via `ACTIVEMQ_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)
- **Variables d'environnement** :
  - `SPRING_PROFILES_ACTIVE=production-microservice`
  - `ACTIVEMQ_URL`, `SPRING_ACTIVEMQ_BROKER_URL`, `SPRING_JMS_ACTIVEMQ_BROKER_URL` (toutes pointent vers le service DNS Kubernetes)
  - `VEHICLE_COUNT=12`
  - `MESSAGE_FREQUENCY_MS=500`
- **Fonction** : Génère des positions de véhicules et les envoie à la queue

### 4. **fleetman-position-tracker** (Consommateur + API)
- **Type** : Deployment (2 réplicas)
- **Image** : `supinfo4kube/position-tracker:1.1.0`
- **Dépend de** :
  - `fleetman-queue` (consomme les messages via `tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)
  - `fleetman-mongodb` (stocke les positions via `mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman`)
- **Variables d'environnement** :
  - `SPRING_PROFILES_ACTIVE=production-microservice`
  - `SPRING_DATA_MONGODB_URI`, `SPRING_DATA_MONGODB_DATABASE=fleetman`
  - `SPRING_JMS_LISTENER_AUTO_STARTUP=true`
  - `SPRING_MAIN_ALLOW_BEAN_DEFINITION_OVERRIDING=true`
- **API REST** : Expose `/vehicles/` sur le port 8080
- **Utilisé par** : `fleetman-api-gateway`, `fleetman-web-app` (via Nginx)

### 5. **fleetman-api-gateway** (Passerelle API)
- **Type** : Deployment (2 réplicas)
- **Image** : `supinfo4kube/api-gateway:1.1.0`
- **Dépend de** :
  - `fleetman-position-tracker` (appelle l'API via `http://fleetman-position-tracker.fleetman.svc.cluster.local:8080`)
  - `fleetman-mongodb` (accès direct via `mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman`)
- **Variables d'environnement** :
  - `SPRING_PROFILES_ACTIVE=production-microservice`
  - `FLEETMAN_POSITION_TRACKER_URL`, `SPRING_DATA_MONGODB_URI`, `SPRING_DATA_MONGODB_DATABASE`
  - `SPRING_CLOUD_GATEWAY_ROUTES_*` (configuration des routes)
  - `SPRING_MAIN_ALLOW_BEAN_DEFINITION_OVERRIDING=true`
- **Utilisé par** : `fleetman-web-app` (pour certaines routes `/api/`)

### 6. **fleetman-history-service** (Service historique)
- **Type** : Deployment (1 replica)
- **Image** : `python:3.9-slim`
- **Dépend de** : `fleetman-mongodb` (lit directement la collection `vehiclePosition`)
- **Fonction** : Service Python Flask qui expose `/api/vehicles/{name}/history` pour récupérer l'historique des positions d'un véhicule
- **Variables d'environnement** :
  - `MONGODB_HOST=fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`
  - `MONGODB_PORT=27017`
  - `MONGODB_DB=fleetman`
- **Utilisé par** : `fleetman-web-app` (via Nginx pour les routes `/api/vehicles/{id}/history`)

### 7. **fleetman-positions-adapter** (Adapter Nginx)
- **Type** : Deployment (1 replica) + ConfigMap
- **Image** : `nginx:alpine`
- **Fonction** : Adapter Nginx pour le Position Tracker (optionnel, peut être utilisé par l'API Gateway)
- **Utilisé par** : Potentiellement `fleetman-api-gateway` (selon configuration)

### 8. **fleetman-web-app** (Frontend)
- **Type** : Deployment (2 réplicas)
- **Image** : `supinfo4kube/web-app:1.1.0`
- **Service** : NodePort (port 30080)
- **Dépend de** :
  - `fleetman-position-tracker` (via Nginx pour `/api/vehicles/`)
  - `fleetman-history-service` (via Nginx pour `/api/vehicles/{id}/history`)
  - `fleetman-api-gateway` (via Nginx pour autres routes `/api/`)
  - `fleetman-webapp-nginx` ConfigMap (configuration Nginx)

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
kubectl apply -f k8s/fleetman-mongodb.yaml

# 3. Déployer la queue ActiveMQ (nécessaire pour les messages)
kubectl apply -f k8s/fleetman-queue.yaml

# 4. Déployer le ConfigMap Nginx (nécessaire pour la webapp)
kubectl apply -f k8s/fleetman-webapp-config.yaml

# 5. Déployer le simulateur (peut démarrer en parallèle)
kubectl apply -f k8s/fleetman-position-simulator.yaml

# 6. Déployer le tracker (dépend de MongoDB et Queue)
kubectl apply -f k8s/fleetman-position-tracker.yaml

# 7. Déployer l'API Gateway (dépend du tracker)
kubectl apply -f k8s/fleetman-api-gateway.yaml

# 8. Déployer le History Service (dépend de MongoDB)
kubectl apply -f k8s/fleetman-history-service.yaml

# 9. Déployer le Positions Adapter (optionnel)
kubectl apply -f k8s/fleetman-positions-adapter.yaml

# 10. Déployer l'application web (dépend de l'API Gateway, Tracker, History Service et du ConfigMap)
kubectl apply -f k8s/fleetman-web-app.yaml
```

### Vérification du déploiement

```bash
# Vérifier tous les pods
kubectl get pods -n fleetman

# Vérifier tous les services
kubectl get svc -n fleetman

# Vérifier les déploiements
kubectl get deployments -n fleetman

# Vérifier MongoDB (StatefulSet)
kubectl get statefulset -n fleetman

# Vérifier les volumes persistants
kubectl get pvc -n fleetman

# Vue d'ensemble
kubectl get all -n fleetman
```

---

## 📖 Explication détaillée des fichiers

### 1. `namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: fleetman
```

**Fonction** :
- Crée un namespace isolé nommé `fleetman` pour toutes les ressources de l'application
- Permet d'organiser et d'isoler les ressources Kubernetes

**Pourquoi c'est important** :
- Évite les conflits de noms avec d'autres applications
- Permet de gérer les permissions et quotas par namespace
- Facilite la suppression de toute l'application d'un coup

---

### 2. `fleetman-mongodb.yaml`

**Contient** : Service Headless + StatefulSet

#### Service Headless

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fleetman-mongodb
  namespace: fleetman
spec:
  clusterIP: None  # Service Headless
  selector:
    app: fleetman-mongodb
  ports:
    - name: mongo
      port: 27017
      targetPort: 27017
```

**Fonction** :
- Service Headless (`clusterIP: None`) : permet un accès direct aux pods MongoDB
- Expose le port 27017 (port standard MongoDB)
- Chaque pod MongoDB a un nom DNS stable : `fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`

**Pourquoi Headless Service** :
- Permet la découverte directe des pods pour la réplication MongoDB
- Nécessaire pour les StatefulSets qui ont besoin d'identités stables

#### StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: fleetman-mongodb
spec:
  serviceName: fleetman-mongodb  # Référence au service Headless
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
- **StatefulSet** : Gère les pods avec identité stable (nom : `fleetman-mongodb-0`)
- **volumeClaimTemplates** : Crée automatiquement un PVC (`data-fleetman-mongodb-0`) de 5Gi pour chaque pod
- Le volume est monté dans `/data/db` (répertoire par défaut de MongoDB)
- **Probes** : `readinessProbe` et `livenessProbe` utilisent `db.adminCommand('ping')` avec timeouts appropriés

**Pourquoi StatefulSet et pas Deployment** :
- **Persistance** : Les données MongoDB doivent survivre aux redémarrages
- **Identité stable** : Le pod garde toujours le même nom et le même volume
- **Ordre de déploiement** : Important pour la réplication MongoDB

**Liens avec autres composants** :
- Utilisé par `fleetman-position-tracker` via `SPRING_DATA_MONGODB_URI=mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman`
- Utilisé par `fleetman-api-gateway` via `SPRING_DATA_MONGODB_URI=mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman`
- Utilisé par `fleetman-history-service` via `MONGODB_HOST=fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`

---

### 3. `fleetman-queue.yaml`

**Contient** : Deployment + Service ClusterIP

#### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-queue
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
- **Image** : `supinfo4kube/queue:1.1.0` (ActiveMQ 5.17.3)
- **Réplicas** : 2 (haute disponibilité)
- Port 61616 : Pour les messages OpenWire (utilisé par simulator et tracker)
- Port 8161 : Interface web de gestion ActiveMQ

#### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fleetman-queue
spec:
  type: ClusterIP
  ports:
    - name: openwire
      port: 61616
      targetPort: 61616
    - name: ui
      port: 8161
      targetPort: ui
```

**Fonction** :
- Expose ActiveMQ dans le cluster via ClusterIP
- Les autres pods peuvent accéder via `fleetman-queue.fleetman.svc.cluster.local:61616` (DNS Kubernetes complet)

**Liens avec autres composants** :
- Utilisé par `fleetman-position-simulator` via `ACTIVEMQ_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`
- Utilisé par `fleetman-position-tracker` via `SPRING_ACTIVEMQ_BROKER_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`

---

### 4. `fleetman-position-simulator.yaml`

**Contient** : Deployment + Service

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-position-simulator
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
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: SPRING_ACTIVEMQ_BROKER_URL
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: SPRING_JMS_ACTIVEMQ_BROKER_URL
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: VEHICLE_COUNT
              value: "12"
            - name: MESSAGE_FREQUENCY_MS
              value: "500"
```

**Fonction** :
- **Producteur de messages** : Génère des positions de véhicules simulées
- Envoie les messages à ActiveMQ via `fleetman-queue:61616`
- **VEHICLE_COUNT** : Nombre de véhicules à simuler (12)
- **MESSAGE_FREQUENCY_MS** : Fréquence d'envoi (toutes les 500ms)

**Flux** :
1. Génère des positions GPS aléatoires pour 12 véhicules
2. Envoie chaque position à la queue ActiveMQ
3. Répète toutes les 500ms

**Liens avec autres composants** :
- **Dépend de** : `fleetman-queue` (doit être déployé avant)
- **Produit pour** : `fleetman-position-tracker` (consomme les messages)

---

### 5. `fleetman-position-tracker.yaml`

**Contient** : Deployment + Service ClusterIP

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-position-tracker
spec:
  replicas: 2  # Haute disponibilité
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/position-tracker:1.1.0
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: production-microservice
            - name: ACTIVEMQ_URL
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: SPRING_ACTIVEMQ_BROKER_URL
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: SPRING_JMS_ACTIVEMQ_BROKER_URL
              value: tcp://fleetman-queue.fleetman.svc.cluster.local:61616
            - name: SPRING_DATA_MONGODB_URI
              value: mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman
            - name: SPRING_DATA_MONGODB_DATABASE
              value: fleetman
            - name: SPRING_JMS_LISTENER_AUTO_STARTUP
              value: "true"
            - name: SPRING_MAIN_ALLOW_BEAN_DEFINITION_OVERRIDING
              value: "true"
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
1. Consomme les messages de `fleetman-queue`
2. Stocke chaque position dans MongoDB (`fleetman` database)
3. Expose une API REST pour récupérer les positions stockées

**Liens avec autres composants** :
- **Dépend de** :
  - `fleetman-queue` (consomme les messages)
  - `fleetman-mongodb` (stocke les données)
- **Utilisé par** : `fleetman-api-gateway` (appelle l'API REST)

---

### 6. `fleetman-api-gateway.yaml`

**Contient** : Deployment + Service ClusterIP

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-api-gateway
spec:
  replicas: 2  # Haute disponibilité
  template:
    spec:
      containers:
        - name: app
          image: supinfo4kube/api-gateway:1.1.0
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: production-microservice
            - name: FLEETMAN_POSITION_TRACKER_URL
              value: http://fleetman-position-tracker.fleetman.svc.cluster.local:8080
            - name: SPRING_DATA_MONGODB_URI
              value: mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman
            - name: SPRING_DATA_MONGODB_DATABASE
              value: fleetman
            - name: SPRING_CLOUD_GATEWAY_ROUTES_0_ID
              value: position-tracker
            - name: SPRING_CLOUD_GATEWAY_ROUTES_0_URI
              value: http://fleetman-position-tracker.fleetman.svc.cluster.local:8080
            - name: SPRING_CLOUD_GATEWAY_ROUTES_0_PREDICATES_0
              value: Path=/api/vehicles/**
            - name: SPRING_CLOUD_GATEWAY_ROUTES_0_FILTERS_0
              value: RewritePath=/api/vehicles/(?<path>.*),/vehicles/${path}
            - name: SPRING_MAIN_ALLOW_BEAN_DEFINITION_OVERRIDING
              value: "true"
```

**Fonction** :
- **Passerelle API** : Point d'entrée unique pour le backend
- **Aggrégation** : Combine les données de plusieurs sources
- **2 réplicas** : Pour la haute disponibilité

**URL complète du tracker** :
- `http://fleetman-position-tracker.fleetman.svc.cluster.local:8080`
- Format DNS Kubernetes : `<service>.<namespace>.svc.cluster.local:<port>`
- Permet l'accès même si le service est dans un autre namespace

**Liens avec autres composants** :
- **Dépend de** :
  - `fleetman-position-tracker` (appelle l'API)
  - `fleetman-mongodb` (accès direct pour certaines requêtes)
- **Utilisé par** : `fleetman-web-app` (appelle l'API Gateway)

---

### 7. `fleetman-web-app.yaml`

**Contient** : Deployment + Service NodePort

#### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-web-app
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: webapp
          image: supinfo4kube/web-app:1.1.0
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
      volumes:
        - name: nginx-config
          configMap:
            name: fleetman-webapp-nginx
```

**Fonction** :
- **Frontend** : Application web (Nginx + HTML/JS)
- **2 réplicas** : Pour la haute disponibilité
- **ConfigMap** : Utilise `fleetman-webapp-nginx` pour la configuration Nginx
- **API_GATEWAY_URL** : Chemin relatif `/api` pour appeler l'API Gateway

**Note** : Le ConfigMap `fleetman-webapp-nginx` doit être créé séparément (non inclus dans ce fichier).

#### Service NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fleetman-web-app
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 30080
```

**Fonction** :
- **NodePort** : Expose l'application à l'extérieur du cluster
- **Port 30080** : Accessible depuis n'importe quel nœud du cluster
- **Port 80** : Port interne du service

**Liens avec autres composants** :
- **Dépend de** : 
  - `fleetman-api-gateway` (appelle `/api` qui pointe vers l'API Gateway)
  - `fleetman-webapp-nginx` ConfigMap (configuration Nginx)

---

### 8. `fleetman-webapp-config.yaml`

**Contient** : ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fleetman-webapp-nginx
  namespace: fleetman
data:
  nginx.conf: |
    # Configuration Nginx complète
    upstream api_gateway {
      server fleetman-api-gateway.fleetman.svc.cluster.local:8080;
    }
    # Proxy /api/ vers l'API Gateway
    location /api/ {
      proxy_pass http://api_gateway/;
    }
```

**Fonction** :
- **ConfigMap** : Stocke la configuration Nginx complète pour la webapp
- **Proxy reverse** : Configure Nginx pour router les requêtes vers les différents backends
- **Routes configurées** :
  - `/api/vehicles/{id}/history` → `fleetman-history-service` (historique des positions)
  - `/api/vehicles/` → `fleetman-position-tracker` (liste et positions en temps réel)
  - `/api/` → `fleetman-api-gateway` (autres routes API)
- **Timeouts** : `proxy_connect_timeout`, `proxy_send_timeout`, `proxy_read_timeout` à 60s pour éviter les 504
- **CORS** : Headers CORS configurés pour toutes les routes API
- **DNS Resolver** : `resolver kube-dns.kube-system.svc.cluster.local valid=10s` pour la résolution DNS dynamique

**Pourquoi c'est nécessaire** :
- La webapp (`fleetman-web-app.yaml`) monte ce ConfigMap dans `/etc/nginx/nginx.conf`
- Sans ce ConfigMap, Nginx ne saurait pas où rediriger les requêtes API
- Permet de séparer la configuration du code de l'application
- Permet le routage intelligent vers différents services backend

**Liens avec autres composants** :
- **Utilisé par** : `fleetman-web-app` (monté comme volume dans le pod)

---

### 9. `fleetman-history-service.yaml`

**Contient** : Deployment + Service

**Fonction** :
- **Service Python Flask** : Expose l'historique des positions de véhicules
- **Image** : `python:3.9-slim`
- **Endpoints** :
  - `/health` : Health check
  - `/api/vehicles/{name}/history` : Historique des positions d'un véhicule
  - `/api/vehicles/{name}/positions` : Alias de `/history`
- **Connexion MongoDB** : Lit directement la collection `vehiclePosition` via FQDN
- **Variables d'environnement** :
  - `MONGODB_HOST=fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`
  - `MONGODB_PORT=27017`
  - `MONGODB_DB=fleetman`

**Liens avec autres composants** :
- **Dépend de** : `fleetman-mongodb` (lit la collection `vehiclePosition`)
- **Utilisé par** : `fleetman-web-app` (via Nginx pour les routes `/api/vehicles/{id}/history`)

### 10. `fleetman-positions-adapter.yaml`

**Contient** : Deployment + Service + ConfigMap

**Fonction** :
- **Adapter Nginx** : Proxy Nginx pour le Position Tracker
- **Image** : `nginx:alpine`
- **ConfigMap** : Configuration Nginx pour router vers `fleetman-position-tracker`

**Note** : Ce service est optionnel et peut être utilisé par l'API Gateway selon la configuration.

**Liens avec autres composants** :
- **Dépend de** : `fleetman-position-tracker`
- **Utilisé par** : Potentiellement `fleetman-api-gateway` (selon configuration)

---

## 🔄 Flux de données

### Flux complet de bout en bout

```
1. fleetman-position-simulator
   └─> Génère des positions GPS (12 véhicules, toutes les 500ms)
       └─> Envoie à fleetman-queue (ActiveMQ) via AMQP

2. fleetman-queue (ActiveMQ)
   └─> Stocke les messages dans une queue
       └─> Distribue aux consommateurs

3. fleetman-position-tracker
   └─> Consomme les messages de fleetman-queue
       ├─> Stocke dans fleetman-mongodb (base de données)
       └─> Expose une API REST sur le port 8080 (`/vehicles/`)

4. fleetman-api-gateway
   └─> Appelle fleetman-position-tracker (API REST)
       ├─> Peut aussi lire directement fleetman-mongodb
       └─> Agrège et expose une API unifiée

5. fleetman-history-service
   └─> Lit directement fleetman-mongodb
       └─> Expose `/api/vehicles/{name}/history` pour l'historique

6. fleetman-web-app
   └─> Route les requêtes via Nginx :
       ├─> `/api/vehicles/` → fleetman-position-tracker
       ├─> `/api/vehicles/{id}/history` → fleetman-history-service
       └─> `/api/` → fleetman-api-gateway
       └─> Affiche les positions sur une carte web

7. Utilisateur
   └─> Accède à http://<node-ip>:30080
       └─> Voit la carte avec les positions en temps réel
       └─> Peut cliquer sur un véhicule pour voir sa trace
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
   └─> Se connecte à fleetman-queue:61616
   └─> Commence à envoyer des messages

4. Tracker démarre (Deployment)
   └─> Se connecte à fleetman-queue:61616 (consomme)
   └─> Se connecte à fleetman-mongodb:27017 (stocke)
   └─> Démarre l'API REST sur le port 8080
   └─> readinessProbe vérifie que le port 8080 répond

5. API Gateway démarre (Deployment)
   └─> Se connecte à fleetman-position-tracker (HTTP)
   └─> Se connecte à fleetman-mongodb (optionnel)
   └─> readinessProbe vérifie que le port 8080 répond

6. Web App démarre (Deployment)
   └─> Charge la config Nginx depuis ConfigMap
   └─> readinessProbe vérifie que le port 80 répond
   └─> Accessible via NodePort 30080
```

---

## 🌐 Accès à l'application

### Accès externe (NodePort)

```bash
# Trouver l'IP d'un nœud worker
kubectl get nodes -o wide

# Accéder à l'application
http://<IP_WORKER>:30080
```

Exemple :
- `http://192.168.xx.xx:30080` (worker1)
- `http://192.168.xx.xx:30080` (worker2)

### Accès local (Port Forward)

```bash
kubectl -n fleetman port-forward svc/fleetman-web-app 30080:80
```

Puis ouvrir : `http://localhost:30080`

### Accès à la console ActiveMQ

```bash
# Port-forward vers la console ActiveMQ
kubectl -n fleetman port-forward svc/fleetman-queue 8161:8161
```

Puis ouvrir : `http://localhost:8161` (admin/admin par défaut)

---

## 🔧 Dépannage

### Vérifier l'état des pods

```bash
# Voir tous les pods
kubectl get pods -n fleetman

# Voir les détails d'un pod en erreur
kubectl describe pod <nom-du-pod> -n fleetman

# Voir les logs d'un pod
kubectl logs <nom-du-pod> -n fleetman

# Suivre les logs en temps réel
kubectl logs -f <nom-du-pod> -n fleetman
```

### Vérifier les services et endpoints

```bash
# Voir tous les services
kubectl get svc -n fleetman

# Voir les endpoints (pods associés aux services)
kubectl get endpoints -n fleetman

# Détails d'un service
kubectl describe svc <nom-service> -n fleetman
```

### Vérifier MongoDB

```bash
# Voir le StatefulSet
kubectl get statefulset fleetman-mongodb -n fleetman

# Voir le pod MongoDB
kubectl get pods -n fleetman | grep mongodb

# Voir les logs MongoDB
kubectl logs fleetman-mongodb-0 -n fleetman

# Vérifier le PVC
kubectl get pvc -n fleetman

# Détails du PVC
kubectl describe pvc data-fleetman-mongodb-0 -n fleetman
```

### Vérifier la connectivité entre services

```bash
# Tester depuis un pod tracker vers l'API Gateway
kubectl exec -n fleetman -it <pod-tracker> -- \
  curl -sS http://fleetman-api-gateway:8080/actuator/health

# Tester depuis un pod tracker vers MongoDB
kubectl exec -n fleetman -it <pod-tracker> -- \
  nc -zv fleetman-mongodb 27017

# Tester depuis un pod tracker vers la queue
kubectl exec -n fleetman -it <pod-tracker> -- \
  nc -zv fleetman-queue 61616
```

### Redémarrer un composant

```bash
# Redémarrer un déploiement
kubectl rollout restart deploy/fleetman-queue -n fleetman

# Redémarrer un StatefulSet
kubectl rollout restart statefulset/fleetman-mongodb -n fleetman

# Supprimer un pod (sera recréé automatiquement)
kubectl delete pod <nom-du-pod> -n fleetman
```

### Problèmes courants

1. **Pods en CrashLoopBackOff**
   - Vérifier les logs : `kubectl logs <pod> -n fleetman`
   - Vérifier que les dépendances sont prêtes (MongoDB, Queue)

2. **Pods en ImagePullBackOff**
   - Vérifier que les images Docker existent
   - Vérifier les permissions du registry

3. **Service sans endpoints**
   - Vérifier que les pods ont les bons labels
   - Vérifier que les pods sont READY (readinessProbe)

4. **MongoDB ne démarre pas**
   - Vérifier que le PVC est créé : `kubectl get pvc -n fleetman`
   - Vérifier la StorageClass : `kubectl get storageclass`

---

## 🗑️ Suppression

### Supprimer l'application complète

```bash
# Supprimer tous les déploiements
kubectl delete -f k8s/fleetman-*.yaml --namespace=fleetman

# Supprimer le namespace (supprime tout)
kubectl delete ns fleetman
```

### Supprimer uniquement les ressources (garder le namespace)

```bash
# Supprimer chaque composant individuellement
kubectl delete -f k8s/fleetman-mongodb.yaml
kubectl delete -f k8s/fleetman-queue.yaml
kubectl delete -f k8s/fleetman-position-simulator.yaml
kubectl delete -f k8s/fleetman-position-tracker.yaml
kubectl delete -f k8s/fleetman-api-gateway.yaml
kubectl delete -f k8s/fleetman-web-app.yaml
```

**Note** : Les PVC (volumes persistants) ne sont pas supprimés automatiquement. Pour les supprimer :

```bash
kubectl delete pvc -n fleetman --all
```

---

## 📊 Résumé des ressources

| Ressource | Nombre | Type |
|-----------|--------|------|
| **Namespace** | 1 | `fleetman` |
| **StatefulSet** | 1 | `fleetman-mongodb` (1 replica) |
| **Deployments** | 7 | Queue (2), Simulator (1), Tracker (2), API Gateway (2), History Service (1), Positions Adapter (1), Web App (2) |
| **Services** | 8 | 7 ClusterIP + 1 NodePort |
| **ConfigMaps** | 2 | `fleetman-webapp-nginx`, `fleetman-positions-adapter-nginx` |
| **PVC** | 1 | `data-fleetman-mongodb-0` (5Gi) |
| **Total Pods** | 12 | 1 MongoDB + 2 Queue + 1 Simulator + 2 Tracker + 2 API Gateway + 1 History Service + 1 Positions Adapter + 2 Web App |

---

## 🎯 Points clés à retenir

1. **Ordre de déploiement** : MongoDB → Queue → Simulator → Tracker → API Gateway → History Service → Positions Adapter → Web App
2. **StatefulSet pour MongoDB** : Nécessaire pour la persistance des données
3. **Service Headless pour MongoDB** : Permet l'accès direct aux pods via FQDN (`fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`)
4. **NodePort pour Web App** : Seul service accessible de l'extérieur (port 30080)
5. **Probes** : Readiness et Liveness probes assurent la disponibilité (MongoDB utilise `db.adminCommand('ping')`)
6. **DNS Kubernetes** : Tous les services utilisent des FQDN complets (`<service>.<namespace>.svc.cluster.local`) pour la résolution DNS
7. **ActiveMQ** : Service ClusterIP avec DNS Kubernetes (`tcp://fleetman-queue.fleetman.svc.cluster.local:61616`)
8. **Nginx Routing** : Configuration Nginx avec timeouts (60s) et routage intelligent vers différents backends
9. **History Service** : Service Python Flask pour l'historique des véhicules, lit directement MongoDB
10. **Images** : Toutes les images utilisent la version `1.1.0` (sauf `fleetman-history-service` qui utilise `python:3.9-slim`)

---

## 🔧 Configuration ActiveMQ

**Important** : Tous les microservices Spring Boot utilisent des URLs ActiveMQ via DNS Kubernetes :

- `ACTIVEMQ_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`
- `SPRING_ACTIVEMQ_BROKER_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`
- `SPRING_JMS_ACTIVEMQ_BROKER_URL=tcp://fleetman-queue.fleetman.svc.cluster.local:61616`

**Note sur les versions** : Le broker ActiveMQ utilise la version 5.17.3, tandis que les clients Spring Boot utilisent activemq-client 5.16.5. Cette différence peut causer des EOFException dans les logs, mais le flux de données fonctionne correctement.

## 🔧 Configuration MongoDB

**Important** : Tous les services utilisent le FQDN complet pour MongoDB :

- `SPRING_DATA_MONGODB_URI=mongodb://fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local:27017/fleetman`
- `SPRING_DATA_MONGODB_DATABASE=fleetman`
- `MONGODB_HOST=fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local`

**Collection** : Les positions sont stockées dans la collection `vehiclePosition` (pas `positions`).

## 📚 Ressources supplémentaires

- [Documentation Kubernetes - StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Documentation Kubernetes - Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Documentation Kubernetes - Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Documentation Kubernetes - ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
