#!/bin/bash
set -e

echo "➡ Déploiement MongoDB (StatefulSet + PV)..."
kubectl apply -f ../fleetman-mongodb.yaml

echo "➡ Déploiement ActiveMQ..."
kubectl apply -f ../fleetman-queue.yaml

echo "➡ Attente de MongoDB..."
kubectl wait --for=condition=ready pod -l app=fleetman-mongodb -n fleetman --timeout=300s

echo "➡ Attente de ActiveMQ..."
kubectl wait --for=condition=available deployment/fleetman-queue -n fleetman --timeout=180s

echo "✔ Core services prêts."

