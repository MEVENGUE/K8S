#!/bin/bash
set -e

echo "➡ Déploiement des ConfigMaps..."
kubectl apply -f ../fleetman-webapp-config.yaml

echo "➡ Déploiement Position Simulator..."
kubectl apply -f ../fleetman-position-simulator.yaml

echo "➡ Déploiement Position Tracker..."
kubectl apply -f ../fleetman-position-tracker.yaml

echo "➡ Déploiement Positions Adapter..."
kubectl apply -f ../fleetman-positions-adapter.yaml

echo "➡ Déploiement API Gateway..."
kubectl apply -f ../fleetman-api-gateway.yaml

echo "➡ Déploiement History Service..."
kubectl apply -f ../fleetman-history-service.yaml

echo "➡ Déploiement Web App..."
kubectl apply -f ../fleetman-web-app.yaml

echo "➡ Attente du readiness de tous les services..."
kubectl wait --for=condition=available deployment/fleetman-position-simulator -n fleetman --timeout=240s || echo "⚠ Position Simulator prend plus de temps"
kubectl wait --for=condition=available deployment/fleetman-position-tracker -n fleetman --timeout=240s || echo "⚠ Position Tracker prend plus de temps"
kubectl wait --for=condition=available deployment/fleetman-positions-adapter -n fleetman --timeout=240s || echo "⚠ Positions Adapter prend plus de temps"
echo "➡ Attente de l'API Gateway (peut prendre 2-3 minutes)..."
kubectl wait --for=condition=available deployment/fleetman-api-gateway -n fleetman --timeout=360s || echo "⚠ API Gateway prend plus de temps"
kubectl wait --for=condition=available deployment/fleetman-history-service -n fleetman --timeout=240s || echo "⚠ History Service prend plus de temps"
kubectl wait --for=condition=available deployment/fleetman-web-app -n fleetman --timeout=180s || echo "⚠ Web App prend plus de temps"

echo "✔ Tous les services applicatifs sont prêts."

