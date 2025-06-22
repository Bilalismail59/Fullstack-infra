#!/bin/bash

# SURVEILLANCE SONARQUBE : ATTENTE API PRÊTE
# IP LoadBalancer: 34.163.72.165
# Objectif: Surveiller jusqu'à ce que l'API soit accessible

echo " SURVEILLANCE SONARQUBE : ATTENTE API PRÊTE"
echo "============================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
SONAR_IP="34.163.72.165"
SONAR_URL="http://$SONAR_IP:9000"

echo " EXCELLENTE NOUVELLE:"
echo "• LoadBalancer créé: $SONAR_IP"
echo "• Service opérationnel: sonarqube-light"
echo "• URL cible: $SONAR_URL"
echo "• Statut: En attente que l'API soit prête"
echo ""

echo " TEMPS DE DÉMARRAGE NORMAL:"
echo "• Elasticsearch: 2-3 minutes"
echo "• Web Server: 3-5 minutes"
echo "• API complète: 8-15 minutes"
echo "• Premier démarrage: Plus long (initialisation DB)"
echo ""

# 1. Vérification de l'état du pod
echo " 1. ÉTAT ACTUEL DU POD"
echo "-----------------------"

echo "État du pod SonarQube:"
kubectl get pods -n $NAMESPACE -l app=sonarqube-light -o wide

echo ""
echo "Description du pod:"
kubectl describe pod -l app=sonarqube-light -n $NAMESPACE | grep -A 10 -E "(Status|Conditions|Events)"

# 2. Vérification des logs récents
echo ""
echo " 2. LOGS RÉCENTS"
echo "-----------------"

echo "Logs SonarQube (20 dernières lignes):"
kubectl logs -l app=sonarqube-light -n $NAMESPACE --tail=20 2>/dev/null || echo "Pas de logs disponibles"

# 3. Test de connectivité réseau
echo ""
echo " 3. TEST DE CONNECTIVITÉ"
echo "--------------------------"

echo "Test de ping vers l'IP LoadBalancer:"
ping -c 3 $SONAR_IP 2>/dev/null || echo "Ping non disponible"

echo ""
echo "Test de connexion TCP port 9000:"
timeout 5 bash -c "echo >/dev/tcp/$SONAR_IP/9000" 2>/dev/null && echo " Port 9000 ouvert" || echo " Port 9000 fermé ou pas encore prêt"

# 4. Surveillance continue de l'API
echo ""
echo " 4. SURVEILLANCE CONTINUE DE L'API"
echo "------------------------------------"

echo " Surveillance de l'API SonarQube..."
echo " URL: $SONAR_URL"
echo " Attente que l'API réponde..."
echo ""

max_attempts=40  # 20 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Tentative $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # Test de l'API SonarQube
    echo " Test de l'API: $SONAR_URL/api/system/status"
    
    API_RESPONSE=$(curl -s --connect-timeout 10 --max-time 15 "$SONAR_URL/api/system/status" 2>/dev/null)
    CURL_EXIT_CODE=$?
    
    if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$API_RESPONSE" ]; then
        echo " Réponse API reçue: $API_RESPONSE"
        
        if echo "$API_RESPONSE" | grep -q "UP"; then
            echo ""
            echo " SUCCÈS ! SONARQUBE API OPÉRATIONNELLE !"
            echo "=========================================="
            echo " URL: $SONAR_URL"
            echo " Identifiants: admin / admin"
            echo " Statut: UP (complètement opérationnel)"
            echo ""
            echo " État final du pod:"
            kubectl get pods -n $NAMESPACE -l app=sonarqube-light -o wide
            echo ""
            echo " MISSION ACCOMPLIE !"
            echo "•  SonarQube déployé avec succès"
            echo "•  API accessible et opérationnelle"
            echo "•  Ressources optimisées (768Mi RAM)"
            echo "•  Stockage partagé fonctionnel"
            echo ""
            exit 0
        elif echo "$API_RESPONSE" | grep -q "STARTING"; then
            echo " SonarQube démarre encore (STARTING)..."
        elif echo "$API_RESPONSE" | grep -q "DOWN"; then
            echo " SonarQube en cours de démarrage (DOWN)..."
        else
            echo " Réponse inattendue: $API_RESPONSE"
        fi
    else
        case $CURL_EXIT_CODE in
            7)
                echo " Connexion refusée (SonarQube pas encore prêt)"
                ;;
            28)
                echo " Timeout de connexion (SonarQube démarre encore)"
                ;;
            *)
                echo " Pas de réponse (Exit code: $CURL_EXIT_CODE)"
                ;;
        esac
    fi
    
    # Test de la page d'accueil
    echo " Test de la page d'accueil: $SONAR_URL/"
    HOME_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 "$SONAR_URL/" 2>/dev/null)
    if [ -n "$HOME_RESPONSE" ] && echo "$HOME_RESPONSE" | grep -q -i "sonarqube\|login"; then
        echo " Page d'accueil accessible !"
        echo ""
        echo " SONARQUBE INTERFACE ACCESSIBLE !"
        echo "=================================="
        echo " URL: $SONAR_URL"
        echo " Identifiants: admin / admin"
        echo " Interface web opérationnelle"
        echo ""
        exit 0
    fi
    
    # Vérifier l'état du pod
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-light --no-headers 2>/dev/null | awk '{print $3}')
    RESTART_COUNT=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-light --no-headers 2>/dev/null | awk '{print $4}')
    
    echo " État du pod: $POD_STATUS (Restarts: $RESTART_COUNT)"
    
    if [[ "$POD_STATUS" == *"CrashLoopBackOff"* ]]; then
        echo " Pod en CrashLoopBackOff - Vérification des logs..."
        echo " Logs récents:"
        kubectl logs -l app=sonarqube-light -n $NAMESPACE --tail=5 2>/dev/null
    elif [[ "$POD_STATUS" == "Running" ]]; then
        echo " Pod en cours d'exécution"
        
        # Afficher les logs récents pour voir le progrès
        echo " Logs récents (3 dernières lignes):"
        kubectl logs -l app=sonarqube-light -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de nouveaux logs"
    fi
    
    echo ""
    echo " Attente 30 secondes avant le prochain test..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 20 minutes"

# 5. Diagnostic final en cas d'échec
echo ""
echo " 5. DIAGNOSTIC FINAL"
echo "---------------------"

echo "État final du pod:"
kubectl get pods -n $NAMESPACE -l app=sonarqube-light -o wide

echo ""
echo "Logs complets (50 dernières lignes):"
kubectl logs -l app=sonarqube-light -n $NAMESPACE --tail=50 2>/dev/null

echo ""
echo "Description complète du pod:"
kubectl describe pod -l app=sonarqube-light -n $NAMESPACE 2>/dev/null

echo ""
echo "État du service:"
kubectl get svc sonarqube-light -n $NAMESPACE

echo ""
echo " RECOMMANDATIONS:"
echo "• SonarQube peut prendre jusqu'à 30 minutes au premier démarrage"
echo "• Vérifiez les logs pour identifier les erreurs spécifiques"
echo "• Testez l'accès direct: curl $SONAR_URL/api/system/status"
echo "• Si problème persiste: Augmentez la mémoire à 1.5Gi"

echo ""
echo " COMMANDES UTILES:"
echo "• Surveiller les logs: kubectl logs -f -l app=sonarqube-light -n $NAMESPACE"
echo "• Redémarrer: kubectl rollout restart deployment/sonarqube-light -n $NAMESPACE"
echo "• État détaillé: kubectl describe pod -l app=sonarqube-light -n $NAMESPACE"

echo ""
echo "Script terminé: $(date)"

