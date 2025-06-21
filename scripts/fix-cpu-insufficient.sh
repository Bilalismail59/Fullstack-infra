#!/bin/bash

# Solution pour résoudre le problème de ressources CPU insuffisantes
# Basé sur le diagnostic qui montre: "0/3 nodes are available: 3 Insufficient cpu"

echo " SOLUTION RESSOURCES CPU INSUFFISANTES"
echo "========================================"
echo "Date: $(date)"
echo ""

# Analyse du diagnostic
echo " ANALYSE DU DIAGNOSTIC"
echo "------------------------"
echo " PostgreSQL: Fonctionne parfaitement (10.44.0.54:5432)"
echo " SonarQube: Pod en Pending depuis 12h - Insufficient CPU"
echo " Cluster: Nœuds surchargés (95%, 95%, 57% CPU)"
echo " Mémoire: Surchargée (163% sur certains nœuds)"
echo ""

# Variables
NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"
MONITORING_PASSCODE="monitoring-$(date +%s)-$(openssl rand -hex 4)"

echo " SOLUTION: RESSOURCES ULTRA-RÉDUITES"
echo "--------------------------------------"
echo "• CPU Request: 1000m → 100m (10x moins)"
echo "• CPU Limit: 2000m → 300m (6x moins)"
echo "• Memory Request: 1Gi → 256Mi (4x moins)"
echo "• Memory Limit: 2Gi → 512Mi (4x moins)"
echo ""

# 1. Nettoyer les déploiements existants
echo " 1. NETTOYAGE DES DÉPLOIEMENTS"
echo "--------------------------------"
kubectl delete deployment sonarqube sonarqube-sonarqube --ignore-not-found=true -n $NAMESPACE
kubectl delete statefulset sonarqube-sonarqube --ignore-not-found=true -n $NAMESPACE
kubectl delete pod sonarqube-sonarqube-0 --ignore-not-found=true -n $NAMESPACE

echo " Attente du nettoyage..."
sleep 15

# 2. Déploiement avec ressources ultra-réduites
echo ""
echo " 2. DÉPLOIEMENT AVEC RESSOURCES MINIMALES"
echo "-------------------------------------------"

echo "Déploiement SonarQube avec ressources ultra-réduites..."

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
  --set resources.requests.memory=256Mi \
  --set resources.requests.cpu=100m \
  --set resources.limits.memory=512Mi \
  --set resources.limits.cpu=300m \
  --set sonarProperties."sonar\.es\.bootstrap\.checks\.disable"=true \
  --set monitoringPasscode="$MONITORING_PASSCODE" \
  --set community.enabled=true \
  --set sonarProperties."sonar\.web\.javaOpts"="-Xmx256m -Xms128m" \
  --set sonarProperties."sonar\.ce\.javaOpts"="-Xmx256m -Xms128m"

if [ $? -eq 0 ]; then
    echo " Déploiement Helm réussi avec ressources réduites"
else
    echo " Échec du déploiement Helm"
    exit 1
fi

# 3. Surveillance du démarrage
echo ""
echo " 3. SURVEILLANCE DU DÉMARRAGE"
echo "-------------------------------"

echo " Surveillance des pods SonarQube..."
max_attempts=60  # 30 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -o wide
    
    # Vérifier si le pod est schedulé
    SCHEDULED_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=sonarqube --no-headers 2>/dev/null | grep -v "Pending" | wc -l)
    
    if [ "$SCHEDULED_PODS" -gt 0 ]; then
        echo " Pod SonarQube schedulé avec succès!"
        
        # Vérifier si le pod est en cours d'exécution
        RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=sonarqube --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo " Pod SonarQube en cours d'exécution!"
            
            # Vérifier l'IP du LoadBalancer
            SONAR_IP=$(kubectl get svc sonarqube-sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            
            if [ -n "$SONAR_IP" ]; then
                echo " IP externe: $SONAR_IP"
                SONAR_URL="http://$SONAR_IP:9000"
                
                # Test de l'API
                if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP\|STARTING"; then
                    echo ""
                    echo " SUCCÈS COMPLET!"
                    echo "=================="
                    echo " URL: $SONAR_URL"
                    echo " Identifiants: admin / admin"
                    echo " Passcode: $MONITORING_PASSCODE"
                    echo ""
                    echo " Ressources utilisées:"
                    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                    echo ""
                    exit 0
                fi
            fi
        fi
    fi
    
    # Vérifier les erreurs de scheduling
    PENDING_REASON=$(kubectl describe pod -l app.kubernetes.io/name=sonarqube -n $NAMESPACE 2>/dev/null | grep -A 5 "Events:" | grep "FailedScheduling" | tail -1)
    if [ -n "$PENDING_REASON" ]; then
        echo " Raison du Pending: $PENDING_REASON"
    fi
    
    # Afficher l'utilisation des ressources
    echo ""
    echo " Utilisation actuelle des nœuds:"
    kubectl top nodes 2>/dev/null | head -4 || echo "Métriques non disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 30 minutes"

# 4. Diagnostic en cas d'échec
echo ""
echo " 4. DIAGNOSTIC EN CAS D'ÉCHEC"
echo "------------------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Description du pod SonarQube:"
kubectl describe pod -l app.kubernetes.io/name=sonarqube -n $NAMESPACE 2>/dev/null | grep -A 10 -E "(Events|Conditions)"

echo ""
echo "Utilisation des ressources par nœud:"
kubectl top nodes 2>/dev/null || echo "Métriques non disponibles"

echo ""
echo " SOLUTIONS SUPPLÉMENTAIRES:"
echo "• Réduire encore plus les ressources (50m CPU, 128Mi RAM)"
echo "• Augmenter la taille du cluster GKE"
echo "• Utiliser une version SonarQube plus légère"
echo "• Nettoyer d'autres pods pour libérer des ressources"

echo ""
echo "Script terminé: $(date)"

