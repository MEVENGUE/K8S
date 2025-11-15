#!/bin/bash
set -e # Arrête le script immédiatement si une commande échoue

# Définir des couleurs pour une sortie plus claire
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Pas de couleur

echo -e "${YELLOW}Étape 1 : Création du Namespace...${NC}"
kubectl apply -f namespace.yaml
echo -e "${GREEN}Namespace créé.${NC}\n"

echo -e "${YELLOW}Étape 2 : Déploiement de MongoDB et de la Queue (dépendances de base)...${NC}"
kubectl apply -f trucks-mongodb.yaml
kubectl apply -f trucks-queue.yaml
echo -e "${GREEN}MongoDB et Queue déployés.${NC}\n"

echo -e "${YELLOW}Étape 3 : Attente du démarrage de la DB et de la Queue (peut prendre 1-2 minutes)...${NC}"
# MongoDB est un StatefulSet, on attend que le pod soit prêt
kubectl wait --for=condition=ready pod -l app=trucks-mongodb -n trucks --timeout=300s
kubectl wait --for=condition=available deployment/trucks-queue -n trucks --timeout=180s
echo -e "${GREEN}DB et Queue prêtes !${NC}\n"

echo -e "${YELLOW}Étape 4 : Déploiement des ConfigMaps nécessaires...${NC}"
kubectl apply -f trucks-webapp-config.yaml
echo -e "${GREEN}ConfigMaps déployés.${NC}\n"

echo -e "${YELLOW}Étape 5 : Déploiement des services applicatifs...${NC}"
kubectl apply -f trucks-position-simulator.yaml
kubectl apply -f trucks-position-tracker.yaml
kubectl apply -f trucks-positions-adapter.yaml
kubectl apply -f trucks-api-gateway.yaml
kubectl apply -f trucks-web-app.yaml
echo -e "${GREEN}Services applicatifs déployés.${NC}\n"

echo -e "${YELLOW}Étape 6 : Attente du démarrage de tous les services applicatifs...${NC}"
kubectl wait --for=condition=available deployment/trucks-position-simulator -n trucks --timeout=180s
kubectl wait --for=condition=available deployment/trucks-position-tracker -n trucks --timeout=180s
kubectl wait --for=condition=available deployment/trucks-positions-adapter -n trucks --timeout=180s
# API Gateway est une application Spring Boot qui prend environ 60-90 secondes à démarrer + probes
echo -e "${YELLOW}Attente du démarrage de l'API Gateway (peut prendre 2-3 minutes)...${NC}"
kubectl wait --for=condition=available deployment/trucks-api-gateway -n trucks --timeout=360s
kubectl wait --for=condition=available deployment/trucks-web-app -n trucks --timeout=180s
echo -e "${GREEN}Toute l'application est 'Running'.${NC}\n"

echo -e "${YELLOW}Étape 7 : Déploiement de l'Ingress (optionnel)...${NC}"
kubectl apply -f trucks-ingress.yaml
echo -e "${GREEN}Ingress déployé.${NC}\n"

echo -e "${YELLOW}Étape 8 : (Fiabilisation) Redémarrage des services pour forcer les connexions...${NC}"
kubectl rollout restart deployment/trucks-queue -n trucks
kubectl rollout restart deployment/trucks-position-simulator -n trucks
kubectl rollout restart deployment/trucks-position-tracker -n trucks
kubectl rollout restart deployment/trucks-api-gateway -n trucks
echo -e "${GREEN}Redémarrage de fiabilisation terminé.${NC}\n"

echo -e "${YELLOW}Étape 9 : Attente de la fin du redémarrage de fiabilisation...${NC}"
# Nous devons attendre que les NOUVEAUX pods soient prêts.
kubectl wait --for=condition=available deployment/trucks-queue -n trucks --timeout=180s
kubectl wait --for=condition=available deployment/trucks-position-simulator -n trucks --timeout=180s
kubectl wait --for=condition=available deployment/trucks-position-tracker -n trucks --timeout=180s
# API Gateway prend du temps à démarrer avec les nouvelles probes
echo -e "${YELLOW}Attente du redémarrage de l'API Gateway...${NC}"
kubectl wait --for=condition=available deployment/trucks-api-gateway -n trucks --timeout=360s
echo -e "${GREEN}Redémarrage de fiabilisation terminé.${NC}\n"

echo -e "${GREEN}--- Déploiement terminé avec succès ! ---${NC}"
echo "L'application devrait être accessible dans quelques instants."
echo "Sur Docker Desktop/Kind : http://localhost:30081"
echo "Via Ingress (si configuré) : http://trucks.local"
