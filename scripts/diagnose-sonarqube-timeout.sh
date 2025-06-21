#!/bin/bash

# Script de diagnostic complet pour SonarQube
# Identifie pourquoi SonarQube prend plus de 45 minutes à démarrer

echo " DIAGNOSTIC COMPLET SONARQUBE"
echo "==============================="
echo "Date: $(date)"
echo ""

# 1. État général du cluster
echo " 1. ÉTAT GÉNÉRAL DU CLUSTER"
echo "-----------------------------"
echo "Nœuds du cluster:"
kubectl get nodes -o wide

echo ""
echo "Utilisation des ressources par nœud:"
kubectl top nodes 2>/dev/null || echo " Metrics server non disponible"

echo ""
echo "Pods en cours d'exécution:"
kubectl get pods --all-namespaces | grep -E "(Running|Pending|Error|CrashLoopBackOff)"

# 2. État spécifique du namespace SonarQube
echo ""
echo " 2. ÉTAT NAMESPACE SONARQUBE"
echo "------------------------------"
echo "Pods SonarQube:"
kubectl get pods -n sonarqube -o wide

echo ""
echo "Services SonarQube:"
kubectl get svc -n sonarqube

echo ""
echo "PVCs SonarQube:"
kubectl get pvc -n sonarqube

echo ""
echo "Événements récents dans le namespace:"
kubectl get events -n sonarqube --sort-by='.lastTimestamp' | tail -20

# 3. Diagnostic détaillé des pods SonarQube
echo ""
echo " 3. DIAGNOSTIC DÉTAILLÉ PODS SONARQUBE"
echo "----------------------------------------"

SONAR_PODS=$(kubectl get pods -n sonarqube -l app.kubernetes.io/name=sonarqube -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$SONAR_PODS" ]; then
    for pod in $SONAR_PODS; do
        echo ""
        echo "=== Pod: $pod ==="
        
        echo "État du pod:"
        kubectl describe pod $pod -n sonarqube | grep -A 10 -E "(Status|Conditions|Events)"
        
        echo ""
        echo "Logs récents (50 dernières lignes):"
        kubectl logs $pod -n sonarqube --tail=50 2>/dev/null || echo "Pas de logs disponibles"
        
        echo ""
        echo "Utilisation des ressources:"
        kubectl top pod $pod -n sonarqube 2>/dev/null || echo "Métriques non disponibles"
    done
else
    echo " Aucun pod SonarQube trouvé"
fi

# 4. Diagnostic PostgreSQL
echo ""
echo "🗄️ 4. DIAGNOSTIC POSTGRESQL"
echo "---------------------------"

POSTGRES_PODS=$(kubectl get pods -n sonarqube -l app=postgres -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$POSTGRES_PODS" ]; then
    for pod in $POSTGRES_PODS; do
        echo ""
        echo "=== PostgreSQL Pod: $pod ==="
        
        echo "État du pod:"
        kubectl describe pod $pod -n sonarqube | grep -A 5 -E "(Status|Ready)"
        
        echo ""
        echo "Test de connexion:"
        kubectl exec $pod -n sonarqube -- pg_isready -U sonarqube -d sonarqube 2>/dev/null || echo " PostgreSQL non accessible"
        
        echo ""
        echo "Logs PostgreSQL (20 dernières lignes):"
        kubectl logs $pod -n sonarqube --tail=20 2>/dev/null || echo "Pas de logs disponibles"
    done
else
    echo " Aucun pod PostgreSQL trouvé"
fi

# 5. Analyse des ressources disponibles
echo ""
echo " 5. ANALYSE DES RESSOURCES"
echo "----------------------------"

echo "Quotas et limites:"
kubectl describe quota -n sonarqube 2>/dev/null || echo "Pas de quotas configurés"

echo ""
echo "Utilisation du stockage:"
kubectl get pv | grep sonarqube 2>/dev/null || echo "Pas de volumes persistants SonarQube"

echo ""
echo "Capacité des nœuds:"
kubectl describe nodes | grep -A 5 "Allocated resources" | head -20

# 6. Vérification de la connectivité réseau
echo ""
echo " 6. VÉRIFICATION RÉSEAU"
echo "------------------------"

echo "Services LoadBalancer:"
kubectl get svc -n sonarqube -o wide | grep LoadBalancer

echo ""
echo "Endpoints des services:"
kubectl get endpoints -n sonarqube

# 7. Analyse des erreurs communes
echo ""
echo " 7. ANALYSE DES ERREURS COMMUNES"
echo "----------------------------------"

echo "Recherche d'erreurs dans les logs SonarQube:"
if [ -n "$SONAR_PODS" ]; then
    for pod in $SONAR_PODS; do
        echo ""
        echo "=== Erreurs dans $pod ==="
        kubectl logs $pod -n sonarqube 2>/dev/null | grep -i -E "(error|exception|failed|timeout|out of memory|oom)" | tail -10 || echo "Aucune erreur trouvée"
    done
fi

echo ""
echo "Recherche d'erreurs dans les événements:"
kubectl get events -n sonarqube | grep -i -E "(error|failed|warning)" | tail -10 || echo "Aucune erreur dans les événements"

# 8. Recommandations basées sur l'analyse
echo ""
echo " 8. RECOMMANDATIONS"
echo "--------------------"

# Vérifier les ressources CPU/Mémoire
TOTAL_CPU=$(kubectl top nodes 2>/dev/null | awk 'NR>1 {sum+=$3} END {print sum}' | sed 's/%//')
TOTAL_MEM=$(kubectl top nodes 2>/dev/null | awk 'NR>1 {sum+=$5} END {print sum}' | sed 's/%//')

if [ -n "$TOTAL_CPU" ] && [ "$TOTAL_CPU" -gt 80 ]; then
    echo " CPU cluster surchargé ($TOTAL_CPU%) - Réduire les ressources SonarQube"
fi

if [ -n "$TOTAL_MEM" ] && [ "$TOTAL_MEM" -gt 80 ]; then
    echo " Mémoire cluster surchargée ($TOTAL_MEM%) - Réduire les ressources SonarQube"
fi

# Vérifier si PostgreSQL fonctionne
if kubectl exec -n sonarqube deployment/postgres -- pg_isready -U sonarqube -d sonarqube >/dev/null 2>&1; then
    echo " PostgreSQL fonctionne correctement"
else
    echo " PostgreSQL ne répond pas - Vérifier la base de données"
fi

# Vérifier les PVCs
PENDING_PVCS=$(kubectl get pvc -n sonarqube | grep Pending | wc -l)
if [ "$PENDING_PVCS" -gt 0 ]; then
    echo " $PENDING_PVCS PVC(s) en attente - Problème de stockage"
fi

echo ""
echo " RÉSUMÉ DU DIAGNOSTIC"
echo "======================"
echo "• Vérifiez les logs SonarQube ci-dessus pour les erreurs spécifiques"
echo "• Si CPU/Mémoire surchargés: Réduire les ressources SonarQube"
echo "• Si PostgreSQL ne répond pas: Redémarrer PostgreSQL"
echo "• Si PVCs en attente: Vérifier les quotas de stockage"
echo "• Considérer un déploiement sans --wait pour éviter les timeouts"
echo ""
echo "Diagnostic terminé: $(date)"

