#!/bin/bash

# Script de nettoyage et redéploiement SonarQube avec ressources optimisées
# Usage: ./fix-sonarqube-resources.sh

set -e

NAMESPACE="sonarqube"

echo " NETTOYAGE ET REDÉPLOIEMENT SONARQUBE"
echo "======================================"

# 1. Nettoyage des ressources existantes
echo ""
echo "=== 1. NETTOYAGE DES RESSOURCES EXISTANTES ==="

echo "Suppression des pods en erreur et pending..."
kubectl delete pods --field-selector=status.phase=Failed -n $NAMESPACE --ignore-not-found=true
kubectl delete pods --field-selector=status.phase=Pending -n $NAMESPACE --ignore-not-found=true

echo "Suppression des deployments existants..."
kubectl delete deployment postgres -n $NAMESPACE --ignore-not-found=true
kubectl delete deployment sonarqube -n $NAMESPACE --ignore-not-found=true

echo "Suppression des ReplicaSets orphelins..."
kubectl delete rs --all -n $NAMESPACE --ignore-not-found=true

echo "Attente de la suppression complète..."
sleep 10

# 2. Vérification des ressources disponibles
echo ""
echo "=== 2. VÉRIFICATION DES RESSOURCES DISPONIBLES ==="
kubectl describe nodes | grep -A 5 "Allocated resources"

# 3. Redéploiement PostgreSQL avec ressources réduites
echo ""
echo "=== 3. DÉPLOIEMENT POSTGRESQL OPTIMISÉ ==="
kubectl apply -f kubernetes/postgres-low-resources.yaml

echo "Attente du démarrage de PostgreSQL..."
kubectl wait --for=condition=available deployment/postgres -n $NAMESPACE --timeout=300s

echo "Vérification de PostgreSQL..."
kubectl get pods -n $NAMESPACE -l app=postgres

# Test de connexion PostgreSQL
echo "Test de connexion PostgreSQL..."
kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U sonarqube -d sonarqube -h localhost

# 4. Redéploiement SonarQube avec ressources réduites
echo ""
echo "=== 4. DÉPLOIEMENT SONARQUBE OPTIMISÉ ==="
kubectl apply -f kubernetes/sonarqube-low-resources.yaml

echo "Attente du démarrage de SonarQube (cela peut prendre plusieurs minutes)..."
kubectl wait --for=condition=available deployment/sonarqube -n $NAMESPACE --timeout=600s

# 5. Vérification finale
echo ""
echo "=== 5. VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 6. Informations d'accès
echo ""
echo " INFORMATIONS D'ACCÈS"
echo "======================="

SONARQUBE_IP=$(kubectl get svc sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "En cours d'attribution...")

if [ "$SONARQUBE_IP" != "En cours d'attribution..." ] && [ -n "$SONARQUBE_IP" ]; then
    echo " SonarQube accessible à : http://$SONARQUBE_IP:9000"
else
    echo " IP externe en cours d'attribution. Vérifiez avec :"
    echo "   kubectl get svc sonarqube -n $NAMESPACE"
    echo ""
    echo " Accès local via port-forward :"
    echo "   kubectl port-forward -n $NAMESPACE svc/sonarqube 9000:9000"
    echo "   Puis ouvrir : http://localhost:9000"
fi

echo ""
echo " Identifiants par défaut :"
echo "   Utilisateur : admin"
echo "   Mot de passe : admin"

echo ""
echo " DÉPLOIEMENT TERMINÉ AVEC SUCCÈS !"
echo "===================================="

# 7. Surveillance continue (optionnel)
read -p "Voulez-vous surveiller les pods en temps réel ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Surveillance des pods (Ctrl+C pour arrêter)..."
    kubectl get pods -n $NAMESPACE -w
fi