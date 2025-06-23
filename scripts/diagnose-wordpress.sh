#!/bin/bash

echo " DIAGNOSTIC WORDPRESS COMPLET"
echo "==============================="
echo ""

echo " 1. ÉTAT DES PODS PRODUCTION"
echo "------------------------------"
kubectl get pods -n production -o wide
echo ""

echo " 2. SERVICES ET ENDPOINTS"
echo "---------------------------"
kubectl get svc -n production
echo ""
kubectl get endpoints -n production
echo ""

echo " 3. LOGS WORDPRESS (DERNIÈRES 20 LIGNES)"
echo "-------------------------------------------"
WORDPRESS_POD=$(kubectl get pods -n production -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$WORDPRESS_POD" ]; then
    echo "Pod WordPress trouvé: $WORDPRESS_POD"
    kubectl logs $WORDPRESS_POD -n production --tail=20 || echo " Impossible de récupérer les logs"
else
    echo " Aucun pod WordPress trouvé"
fi
echo ""

echo " 4. DESCRIPTION DU POD WORDPRESS"
echo "----------------------------------"
if [ ! -z "$WORDPRESS_POD" ]; then
    kubectl describe pod $WORDPRESS_POD -n production | grep -A 10 -B 5 "Events:\|Conditions:\|Status:"
else
    echo " Aucun pod à décrire"
fi
echo ""

echo " 5. ÉVÉNEMENTS RÉCENTS"
echo "------------------------"
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector type!=Normal | tail -10
echo ""

echo " 6. TEST CONNECTIVITÉ POSTGRESQL"
echo "----------------------------------"
POSTGRES_POD=$(kubectl get pods -n production -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POSTGRES_POD" ]; then
    echo "Pod PostgreSQL trouvé: $POSTGRES_POD"
    echo "Test de connexion depuis WordPress vers PostgreSQL..."
    kubectl exec $POSTGRES_POD -n production -- pg_isready -h localhost -p 5432 || echo " PostgreSQL non accessible"
    
    echo "Vérification des bases de données:"
    kubectl exec $POSTGRES_POD -n production -- psql -U postgres -c "\l" || echo " Impossible de lister les bases"
else
    echo " Aucun pod PostgreSQL trouvé"
fi
echo ""

echo " 7. CONFIGURATION WORDPRESS"
echo "-----------------------------"
kubectl get deployment wordpress-prod -n production -o yaml | grep -A 5 -B 5 "env:\|WORDPRESS_\|MYSQL_"
echo ""

echo " 8. RESSOURCES ET LIMITES"
echo "---------------------------"
kubectl top pods -n production 2>/dev/null || echo " Metrics server non disponible"
echo ""

echo " RECOMMANDATIONS"
echo "=================="
echo ""

# Analyser les problèmes courants
if kubectl get pods -n production | grep -q "CrashLoopBackOff"; then
    echo " PROBLÈME DÉTECTÉ: Pods en CrashLoopBackOff"
    echo "   Solutions possibles:"
    echo "   1. Vérifier les logs d'erreur"
    echo "   2. Augmenter les ressources (CPU/mémoire)"
    echo "   3. Corriger la configuration de base de données"
    echo "   4. Vérifier les variables d'environnement"
    echo ""
fi

if kubectl get pods -n production | grep -q "Pending"; then
    echo " PROBLÈME DÉTECTÉ: Pods en Pending"
    echo "   Solutions possibles:"
    echo "   1. Vérifier les ressources du cluster"
    echo "   2. Vérifier les contraintes de scheduling"
    echo "   3. Vérifier les volumes persistants"
    echo ""
fi

echo " PROCHAINES ÉTAPES SUGGÉRÉES:"
echo "1. Analyser les logs d'erreur ci-dessus"
echo "2. Vérifier la connectivité PostgreSQL"
echo "3. Ajuster la configuration si nécessaire"
echo "4. Redémarrer les pods si besoin"
echo ""
echo " Diagnostic terminé !"

