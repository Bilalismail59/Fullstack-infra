#!/bin/bash

# Script de diagnostic PostgreSQL pour GitHub Actions
# Usage: ./debug-postgres.sh [namespace]

NAMESPACE=${1:-sonarqube}

echo " DIAGNOSTIC POSTGRESQL - Namespace: $NAMESPACE"
echo "=================================================="

# 1. Vérifier l'état du cluster
echo ""
echo "=== 1. ÉTAT DU CLUSTER ==="
kubectl get nodes -o wide
echo ""
kubectl describe nodes | grep -A 5 "Allocated resources" | head -20

# 2. Vérifier le namespace
echo ""
echo "=== 2. NAMESPACE ==="
kubectl get namespace $NAMESPACE || kubectl create namespace $NAMESPACE

# 3. Vérifier les ressources dans le namespace
echo ""
echo "=== 3. RESSOURCES DANS LE NAMESPACE ==="
kubectl get all -n $NAMESPACE

# 4. Vérifier les PVC
echo ""
echo "=== 4. PERSISTENT VOLUME CLAIMS ==="
kubectl get pvc -n $NAMESPACE
kubectl describe pvc -n $NAMESPACE

# 5. Vérifier les StorageClass
echo ""
echo "=== 5. STORAGE CLASSES ==="
kubectl get storageclass

# 6. Vérifier les pods PostgreSQL
echo ""
echo "=== 6. PODS POSTGRESQL ==="
kubectl get pods -n $NAMESPACE -l app=postgres -o wide

# 7. Décrire les pods PostgreSQL
echo ""
echo "=== 7. DESCRIPTION DES PODS POSTGRESQL ==="
kubectl describe pods -n $NAMESPACE -l app=postgres

# 8. Logs PostgreSQL
echo ""
echo "=== 8. LOGS POSTGRESQL (50 dernières lignes) ==="
kubectl logs -l app=postgres -n $NAMESPACE --tail=50 || echo "Aucun log disponible"

# 9. Événements du namespace
echo ""
echo "=== 9. ÉVÉNEMENTS DU NAMESPACE ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

# 10. Vérifier les ressources système
echo ""
echo "=== 10. UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 11. Test de connectivité PostgreSQL (si le pod existe)
echo ""
echo "=== 11. TEST DE CONNECTIVITÉ ==="
if kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "Running"; then
    echo "Test de connexion PostgreSQL..."
    kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U sonar -d sonar || echo "Connexion échouée"
else
    echo "Aucun pod PostgreSQL en cours d'exécution"
fi

# 12. Vérifier les services
echo ""
echo "=== 12. SERVICES ==="
kubectl get svc -n $NAMESPACE
kubectl describe svc postgres -n $NAMESPACE || echo "Service postgres non trouvé"

# 13. Vérifier les deployments
echo ""
echo "=== 13. DEPLOYMENTS ==="
kubectl get deployment -n $NAMESPACE
kubectl describe deployment postgres -n $NAMESPACE || echo "Deployment postgres non trouvé"

echo ""
echo " DIAGNOSTIC TERMINÉ"
echo "====================="

