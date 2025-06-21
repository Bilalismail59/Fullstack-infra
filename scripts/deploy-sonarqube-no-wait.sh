#!/bin/bash

# Déploiement SonarQube SANS timeout Helm
# Solution alternative pour éviter les timeouts de 45 minutes

echo " DÉPLOIEMENT SONARQUBE SANS TIMEOUT"
echo "====================================="
echo "Date: $(date)"
echo ""

# Variables
NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"
MONITORING_PASSCODE="monitoring-$(date +%s)-$(openssl rand -hex 4)"

echo " Configuration:"
echo "• Namespace: $NAMESPACE"
echo "• Passcode monitoring: $MONITORING_PASSCODE"
echo "• Mode: Déploiement sans --wait"
echo ""

# 1. Préparation
echo " 1. PRÉPARATION"
echo "-----------------"

# Créer le namespace
kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Nettoyer les déploiements existants
echo " Nettoyage des déploiements existants..."
kubectl delete deployment sonarqube --ignore-not-found=true -n $NAMESPACE
kubectl delete deployment sonarqube-sonarqube --ignore-not-found=true -n $NAMESPACE

# Attendre le nettoyage
sleep 10

# 2. Déploiement SonarQube SANS --wait
echo ""
echo " 2. DÉPLOIEMENT SONARQUBE (SANS TIMEOUT)"
echo "------------------------------------------"

echo "Déploiement SonarQube version 2025.3.0..."
echo " Mode sans --wait pour éviter les timeouts"

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace $NAMESPACE \
  --version 2025.3.0 \
  --set postgresql.enabled=false \
  --set postgresql.postgresqlServer=postgres.sonarqube.svc.cluster.local \
  --set postgresql.postgresqlDatabase=sonarqube \
  --set postgresql.postgresqlUsername=sonarqube \
  --set postgresql.postgresqlPassword="$POSTGRES_PASSWORD" \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set service.type=LoadBalancer \
  --set resources.requests.memory=512Mi \
  --set resources.requests.cpu=200m \
  --set resources.limits.memory=1Gi \
  --set resources.limits.cpu=500m \
  --set sonarProperties."sonar\.es\.bootstrap\.checks\.disable"=true \
  --set monitoringPasscode="$MONITORING_PASSCODE" \
  --set community.enabled=true

# Vérifier que le déploiement a été créé
if [ $? -eq 0 ]; then
    echo " Déploiement Helm réussi (sans attendre le démarrage)"
else
    echo " Échec du déploiement Helm"
    exit 1
fi

# 3. Surveillance manuelle du démarrage
echo ""
echo " 3. SURVEILLANCE DU DÉMARRAGE"
echo "-------------------------------"

echo " Surveillance des pods SonarQube..."
echo "Appuyez sur Ctrl+C pour arrêter la surveillance"
echo ""

# Fonction de surveillance
monitor_startup() {
    local max_attempts=120  # 60 minutes (30s * 120)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
        
        # État des pods
        echo " État des pods:"
        kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=sonarqube -o wide 2>/dev/null || echo "Aucun pod SonarQube trouvé"
        
        # Vérifier si un pod est en cours d'exécution
        RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=sonarqube --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo " Pod SonarQube en cours d'exécution détecté!"
            
            # Vérifier l'IP du LoadBalancer
            echo ""
            echo " Vérification du LoadBalancer..."
            SONAR_IP=$(kubectl get svc sonarqube-sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            
            if [ -n "$SONAR_IP" ]; then
                echo " IP externe assignée: $SONAR_IP"
                SONAR_URL="http://$SONAR_IP:9000"
                
                # Test de l'API
                echo " Test de l'API SonarQube..."
                if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP\|STARTING"; then
                    echo " SonarQube API répond!"
                    echo ""
                    echo " DÉPLOIEMENT RÉUSSI!"
                    echo "===================="
                    echo " URL: $SONAR_URL"
                    echo " Identifiants: admin / admin"
                    echo " Passcode monitoring: $MONITORING_PASSCODE"
                    echo ""
                    return 0
                else
                    echo " API pas encore prête, SonarQube démarre encore..."
                fi
            else
                echo " IP externe pas encore assignée..."
            fi
        fi
        
        # Afficher les logs récents en cas de problème
        echo ""
        echo " Logs récents:"
        kubectl logs -l app.kubernetes.io/name=sonarqube -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
        
        # Afficher les événements récents
        echo ""
        echo " Événements récents:"
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -3 2>/dev/null || echo "Pas d'événements"
        
        echo ""
        echo " Attente 30 secondes..."
        sleep 30
        
        attempt=$((attempt + 1))
    done
    
    echo " Timeout atteint après 60 minutes"
    return 1
}

# Lancer la surveillance
monitor_startup

# 4. Diagnostic en cas d'échec
if [ $? -ne 0 ]; then
    echo ""
    echo " 4. DIAGNOSTIC EN CAS D'ÉCHEC"
    echo "------------------------------"
    
    echo "Exécution du diagnostic automatique..."
    if [ -f "/home/ubuntu/scripts/diagnose-sonarqube-timeout.sh" ]; then
        /home/ubuntu/scripts/diagnose-sonarqube-timeout.sh
    else
        echo "Script de diagnostic non trouvé"
    fi
    
    echo ""
    echo " SOLUTIONS POSSIBLES:"
    echo "• Réduire les ressources SonarQube (CPU/mémoire)"
    echo "• Vérifier que PostgreSQL fonctionne"
    echo "• Augmenter les ressources du cluster"
    echo "• Utiliser une version SonarQube plus ancienne"
fi

echo ""
echo "Script terminé: $(date)"

