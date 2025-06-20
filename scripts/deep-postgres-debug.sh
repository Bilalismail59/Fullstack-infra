#!/bin/bash

# Script de diagnostic approfondi PostgreSQL
# Pour comprendre pourquoi PostgreSQL ne démarre toujours pas

NAMESPACE="sonarqube"

echo " DIAGNOSTIC APPROFONDI POSTGRESQL"
echo "==================================="

echo ""
echo "=== 1. ÉTAT ACTUEL DES PODS ==="
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "=== 2. ÉTAT DU DEPLOYMENT POSTGRESQL ==="
kubectl get deployment postgres -n $NAMESPACE -o yaml

echo ""
echo "=== 3. DESCRIPTION DU POD POSTGRESQL ==="
POSTGRES_POD=$(kubectl get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POSTGRES_POD" ]; then
    echo "Pod trouvé: $POSTGRES_POD"
    kubectl describe pod $POSTGRES_POD -n $NAMESPACE
else
    echo "Aucun pod PostgreSQL trouvé"
fi

echo ""
echo "=== 4. LOGS POSTGRESQL ==="
if [ -n "$POSTGRES_POD" ]; then
    echo "Logs du pod $POSTGRES_POD:"
    kubectl logs $POSTGRES_POD -n $NAMESPACE --tail=50 || echo "Pas de logs disponibles"
else
    echo "Aucun pod pour récupérer les logs"
fi

echo ""
echo "=== 5. ÉVÉNEMENTS DU NAMESPACE ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=== 6. ÉTAT DES PVC ==="
kubectl get pvc -n $NAMESPACE
kubectl describe pvc postgres-pv-claim -n $NAMESPACE

echo ""
echo "=== 7. RESSOURCES ACTUELLES DU CLUSTER ==="
kubectl describe nodes | grep -A 5 "Allocated resources"

echo ""
echo "=== 8. SECRETS ==="
kubectl get secrets -n $NAMESPACE
kubectl describe secret postgres-secret -n $NAMESPACE

echo ""
echo "=== 9. SERVICES ==="
kubectl get svc -n $NAMESPACE

echo ""
echo "=== 10. TENTATIVE DE DIAGNOSTIC AVANCÉ ==="

# Vérifier si le pod est en cours de création
if kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "Pending\|ContainerCreating\|Init"; then
    echo "Pod en cours de création/initialisation"
    
    # Attendre un peu et réessayer
    echo "Attente de 30 secondes..."
    sleep 30
    
    echo "État après attente:"
    kubectl get pods -n $NAMESPACE -l app=postgres
    
    # Récupérer les logs si disponibles
    POSTGRES_POD=$(kubectl get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POSTGRES_POD" ]; then
        echo "Nouveaux logs:"
        kubectl logs $POSTGRES_POD -n $NAMESPACE --tail=20 || echo "Pas de logs disponibles"
    fi
fi

echo ""
echo " SUGGESTIONS DE CORRECTION"
echo "============================"

# Analyser les problèmes courants
if kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "Pending"; then
    echo " Pod en état Pending - Problème de ressources ou de scheduling"
    echo "Solutions:"
    echo "1. Vérifier les ressources disponibles"
    echo "2. Vérifier les node selectors"
    echo "3. Vérifier les taints/tolerations"
elif kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "ContainerCreating"; then
    echo " Pod en cours de création - Problème possible avec le volume"
    echo "Solutions:"
    echo "1. Vérifier le PVC"
    echo "2. Vérifier les permissions du volume"
    echo "3. Attendre plus longtemps"
elif kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "CrashLoopBackOff\|Error"; then
    echo " Pod en erreur - Problème de configuration ou de démarrage"
    echo "Solutions:"
    echo "1. Vérifier les logs du conteneur"
    echo "2. Vérifier les variables d'environnement"
    echo "3. Vérifier les permissions du volume"
elif kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "Running"; then
    echo " Pod en cours d'exécution - Problème possible avec les probes"
    echo "Solutions:"
    echo "1. Vérifier les readiness/liveness probes"
    echo "2. Tester la connexion PostgreSQL manuellement"
else
    echo " État inconnu - Diagnostic manuel nécessaire"
fi

echo ""
echo " ACTIONS RECOMMANDÉES"
echo "======================="
echo "1. Examiner les logs ci-dessus"
echo "2. Identifier le problème spécifique"
echo "3. Appliquer la correction appropriée"
echo "4. Si nécessaire, nettoyer et redéployer complètement"

