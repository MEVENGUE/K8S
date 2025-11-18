#!/bin/bash
set -e

echo "🚀 Déploiement complet de Fleetman sur Kubernetes..."
echo ""

# Obtenir le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "📁 Répertoire de travail : $SCRIPT_DIR"
echo ""

echo "➡ Étape 1/4 : Création du namespace..."
bash 01-namespace.sh
echo ""

echo "➡ Étape 2/4 : Déploiement des services de base (MongoDB + ActiveMQ)..."
bash 02-core-services.sh
echo ""

echo "➡ Étape 3/4 : Déploiement des microservices..."
bash 03-app-services.sh
echo ""

echo "➡ Étape 4/4 : Vérification et tests..."
bash 04-verify.sh
echo ""

echo "🎉 Déploiement terminé avec succès !"
echo ""
echo "📌 Application accessible sur : http://localhost:30080"
echo "📌 Pour vérifier l'état : kubectl get pods -n fleetman"
echo "📌 Pour voir les logs : kubectl logs -n fleetman deployment/<nom-deployment>"

