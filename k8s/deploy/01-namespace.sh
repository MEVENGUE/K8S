#!/bin/bash
set -e

echo "➡ Création du namespace fleetman..."
kubectl apply -f ../namespace.yaml
echo "✔ Namespace créé."

