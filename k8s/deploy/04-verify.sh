#!/bin/bash
set -e

echo "➡ Vérification de l'état des pods..."
kubectl get pods -n fleetman

echo ""
echo "➡ Vérification DNS Kubernetes (Position Tracker)..."
kubectl run dns-test-tracker -n fleetman --image=busybox:1.36 --rm -i --restart=Never -- nslookup fleetman-position-tracker.fleetman.svc.cluster.local || echo "⚠ Test DNS terminé"

echo ""
echo "➡ Vérification DNS Kubernetes (API Gateway)..."
kubectl run dns-test-gateway -n fleetman --image=busybox:1.36 --rm -i --restart=Never -- nslookup fleetman-api-gateway.fleetman.svc.cluster.local || echo "⚠ Test DNS terminé"

echo ""
echo "➡ Vérification DNS Kubernetes (MongoDB)..."
kubectl run dns-test-mongo -n fleetman --image=busybox:1.36 --rm -i --restart=Never -- nslookup fleetman-mongodb-0.fleetman-mongodb.fleetman.svc.cluster.local || echo "⚠ Test DNS terminé"

echo ""
echo "➡ Vérification des services..."
kubectl get svc -n fleetman

echo ""
echo "➡ Vérification du NodePort (Web App)..."
kubectl get svc fleetman-web-app -n fleetman -o jsonpath='{.spec.ports[0].nodePort}' && echo " (NodePort actif)"

echo ""
echo "➡ Test de connectivité interne (Position Tracker depuis un pod)..."
kubectl run connectivity-test -n fleetman --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://fleetman-position-tracker.fleetman.svc.cluster.local:8080/vehicles/ || echo "⚠ Test de connectivité terminé"

echo ""
echo "✔ Tests terminés."
echo ""
echo "📌 Pour tester l'application depuis votre machine :"
echo "   http://localhost:30080"
