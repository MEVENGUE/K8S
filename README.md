# Déploiement de l'application Fleetman sur Kubernetes

Ce dossier contient les manifests Kubernetes pour déployer l'application distribuée "Fleetman".

## Prérequis
- Un cluster Kubernetes (non Docker Desktop/Minikube), 1 master + 2 workers
- `kubectl` configuré vers ce cluster
- Une `StorageClass` par défaut fonctionnelle pour provisionner les PVC

## Composants
- `fleetman-queue`: ActiveMQ (broker + console interne)
- `fleetman-position-simulator`: simulateur d'envoi de positions (Spring Boot)
- `fleetman-position-tracker`: consommateur + API REST (Spring Boot)
- `fleetman-api-gateway`: point d'entrée back (Spring Boot)
- `fleetman-webapp`: application web (exposée en NodePort 30080)
- `fleetman-mongodb`: base MongoDB avec stockage persistant (StatefulSet + PVC)

Tous les services internes sont en `ClusterIP` sauf la webapp en `NodePort` (pas d'Ingress requis).

Les profils Spring sont configurés sur `production-microservice` comme demandé. L'image `web-app` utilise le tag `1.0.0` (au lieu de `1.0.0-dockercompose`).

## Déploiement

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/fleetman-mongodb.yaml
kubectl apply -f k8s/fleetman-queue.yaml
kubectl apply -f k8s/fleetman-position-simulator.yaml
kubectl apply -f k8s/fleetman-position-tracker.yaml
kubectl apply -f k8s/fleetman-api-gateway.yaml
kubectl apply -f k8s/fleetman-webapp.yaml
```

Vérifier que tout est prêt:

```bash
kubectl get pods -n fleetman
kubectl get svc -n fleetman
```

## Accès à l'application web

Service exposé en `NodePort` sur le port `30080`:
- URL: `http://<IP_de_n_importe_quel_noeud_worker>:30080`

## Dépannage
- Les positions peuvent ne pas s'afficher immédiatement. Si nécessaire, redémarrer la queue:

```bash
kubectl rollout restart deploy/fleetman-queue -n fleetman
```

- Vérifier la connectivité DNS/service entre microservices:

```bash
kubectl exec -n fleetman -it <pod_du_tracker> -- curl -sS fleetman-api-gateway:8080/actuator/health || true
```

- Vérifier MongoDB:

```bash
kubectl logs -n fleetman statefulset/fleetman-mongodb
kubectl get pvc -n fleetman
```

- En cas d'absence de `StorageClass` par défaut, définir/en créer une selon votre environnement cloud/on-prem.

## Suppression

```bash
kubectl delete -f k8s/ --namespace=fleetman
kubectl delete ns fleetman
```

