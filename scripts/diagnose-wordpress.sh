#!/bin/bash

echo " DIAGNOSTIC WORDPRESS COMPLET"
echo "==============================="
echo ""

echo " 1. ÉTAT DES PODS PRODUCTION"
echo "------------------------------"
kubectl get pods -n production -o wide || echo " Impossible de récupérer les pods"
echo ""

echo " 2. SERVICES ET ENDPOINTS"
echo "---------------------------"
kubectl get svc -n production || echo " Services non accessibles"
kubectl get endpoints -n production || echo " Endpoints non accessibles"
echo ""

echo " 3. LOGS WORDPRESS (DERNIÈRES 20 LIGNES)"
echo "-------------------------------------------"
WORDPRESS_POD=$(kubectl get pods -n production -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$WORDPRESS_POD" ]]; then
    echo "Pod WordPress trouvé : $WORDPRESS_POD"
    kubectl logs $WORDPRESS_POD -n production --tail=20 || echo " Impossible de récupérer les logs"
else
    echo " Aucun pod WordPress trouvé"
fi
echo ""

echo " 4. DESCRIPTION DU POD WORDPRESS"
echo "----------------------------------"
if [[ -n "$WORDPRESS_POD" ]]; then
    kubectl describe pod $WORDPRESS_POD -n production | grep -A 10 -B 5 -E "Events:|Conditions:|Status:" || echo " Impossible de décrire le pod"
else
    echo " Aucun pod à décrire"
fi
echo ""

echo " 5. ÉVÉNEMENTS RÉCENTS (type!=Normal)"
echo "--------------------------------------"
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector type!=Normal | tail -10 || echo " Événements non accessibles"
echo ""

echo " 6. TEST CONNECTIVITÉ POSTGRESQL"
echo "----------------------------------"
POSTGRES_POD=$(kubectl get pods -n production -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$POSTGRES_POD" ]]; then
    echo "Pod PostgreSQL trouvé : $POSTGRES_POD"
    echo "Test de connexion avec pg_isready..."
    kubectl exec $POSTGRES_POD -n production -- pg_isready || echo " PostgreSQL non prêt"

    echo "Liste des bases de données :"
    kubectl exec $POSTGRES_POD -n production -- psql -U postgres -c "\l" || echo " Impossible de lister les bases"
else
    echo " Aucun pod PostgreSQL trouvé"
fi
echo ""

echo " 7. CONFIGURATION WORDPRESS (env vars)"
echo "----------------------------------------"
kubectl get deployment wordpress-prod -n production -o yaml | grep -A 5 -B 5 -E "env:|WORDPRESS_|MYSQL_" || echo " Impossible de récupérer la configuration"
echo ""

echo " 8. UTILISATION DES RESSOURCES (kubectl top pods)"
echo "---------------------------------------------------"
kubectl top pods -n production 2>/dev/null || echo " Metrics server non disponible"
echo ""

echo " RECOMMANDATIONS"
echo "=================="
echo ""

if kubectl get pods -n production | grep -q "CrashLoopBackOff"; then
    echo "  PROBLÈME DÉTECTÉ : Pods en CrashLoopBackOff"
    echo "    Solutions possibles :"
    echo "   - Vérifier les logs"
    echo "   - Vérifier la base de données et les variables d’environnement"
    echo "   - Réviser les ressources CPU/MEM"
    echo ""
fi

if kubectl get pods -n production | grep -q "Pending"; then
    echo "  PROBLÈME DÉTECTÉ : Pods en Pending"
    echo "    Solutions possibles :"
    echo "   - Vérifier les ressources disponibles du cluster"
    echo "   - Vérifier les PVC et les contraintes de scheduling"
    echo ""
fi

echo " PROCHAINES ÉTAPES SUGGÉRÉES"
echo "=============================="
echo "1. Analyser les logs et les événements"
echo "2. Vérifier les connexions à PostgreSQL"
echo "3. Ajuster les configurations/env si besoin"
echo "4. Redémarrer les pods après modification"
echo ""
echo " Diagnostic terminé !"
