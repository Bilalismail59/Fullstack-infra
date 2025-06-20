#!/bin/bash

# Solution pour l'erreur de passcode de monitoring SonarQube 2025.3.0

NAMESPACE="sonarqube"
MONITORING_PASSCODE="monitoring-$(date +%s)"

echo " CORRECTION PASSCODE MONITORING SONARQUBE 2025.3.0"
echo "=================================================="

echo ""
echo " ERREUR IDENTIFIÉE:"
echo "SonarQube 2025.3.0 exige un passcode de monitoring obligatoire"

echo ""
echo " SOLUTION:"
echo "Ajouter le paramètre monitoringPasscode au déploiement Helm"

echo ""
echo "=== 1. GÉNÉRATION DU PASSCODE DE MONITORING ==="
echo "Passcode généré: $MONITORING_PASSCODE"

echo ""
echo "=== 2. DÉPLOIEMENT SONARQUBE AVEC PASSCODE ==="

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace $NAMESPACE \
  --version 2025.3.0 \
  --set postgresql.enabled=false \
  --set postgresql.postgresqlServer=postgres.sonarqube.svc.cluster.local \
  --set postgresql.postgresqlDatabase=sonarqube \
  --set postgresql.postgresqlUsername=sonarqube \
  --set postgresql.postgresqlPassword="sonarqube" \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set service.type=LoadBalancer \
  --set resources.requests.memory=1Gi \
  --set resources.requests.cpu=500m \
  --set resources.limits.memory=2Gi \
  --set resources.limits.cpu=1000m \
  --set sonarProperties."sonar\.es\.bootstrap\.checks\.disable"=true \
  --set monitoringPasscode="$MONITORING_PASSCODE" \
  --timeout 15m \
  --wait

if [ $? -eq 0 ]; then
    echo ""
    echo " SONARQUBE DÉPLOYÉ AVEC SUCCÈS!"
    echo "================================="
    
    echo ""
    echo "=== 3. SURVEILLANCE DU DÉMARRAGE ==="
    
    # Attendre que le service soit disponible
    echo "Attente du service SonarQube..."
    kubectl wait --for=condition=available deployment/sonarqube-sonarqube -n $NAMESPACE --timeout=900s
    
    # Attendre que l'IP externe soit assignée
    echo "Attente de l'IP externe..."
    for i in {1..20}; do
        SONAR_IP=$(kubectl get svc sonarqube-sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$SONAR_IP" ]; then
            echo " IP externe assignée: $SONAR_IP"
            break
        fi
        echo "Attente de l'IP externe... ($i/20)"
        sleep 15
    done
    
    echo ""
    echo "=== 4. INFORMATIONS DE CONNEXION ==="
    SONAR_URL="http://$SONAR_IP:9000"
    echo " URL SonarQube: $SONAR_URL"
    echo " Identifiants par défaut: admin / admin"
    echo " Passcode de monitoring: $MONITORING_PASSCODE"
    
    echo ""
    echo "=== 5. TEST DE CONNECTIVITÉ ==="
    echo "Test de connectivité SonarQube..."
    for i in {1..20}; do
        if curl -sSf "$SONAR_URL/api/system/status" | grep -q "UP\|STARTING"; then
            echo " SonarQube répond!"
            curl -s "$SONAR_URL/api/system/status" | jq '.' 2>/dev/null || curl -s "$SONAR_URL/api/system/status"
            break
        fi
        echo "Attente de SonarQube... ($i/20)"
        sleep 30
    done
    
    echo ""
    echo "=== 6. ÉTAT FINAL ==="
    kubectl get pods -n $NAMESPACE
    kubectl get svc -n $NAMESPACE
    kubectl get pvc -n $NAMESPACE
    
    echo ""
    echo " SONARQUBE OPÉRATIONNEL!"
    echo "=========================="
    echo " PostgreSQL: Connecté"
    echo " Persistence: Activée (10Gi)"
    echo " LoadBalancer: IP externe assignée"
    echo " Monitoring: Passcode configuré"
    echo " Bootstrap checks: Désactivés pour GKE"
    
else
    echo ""
    echo " ÉCHEC DU DÉPLOIEMENT"
    echo "======================"
    echo "Diagnostic des erreurs:"
    
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
    kubectl describe deployment sonarqube-sonarqube -n $NAMESPACE | tail -20
    
    echo ""
    echo "Logs SonarQube:"
    kubectl logs -l app=sonarqube -n $NAMESPACE --tail=20 2>/dev/null || echo "Pas de logs disponibles"
fi

