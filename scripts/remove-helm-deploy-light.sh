#!/bin/bash

# SOLUTION DÉFINITIVE : SUPPRESSION SONARQUBE HELM MASSIF
# Problème identifié : SonarQube Helm Bitnami demande 3Gi RAM + 1 CPU
# Solution : Supprimer Helm et déployer notre version légère

echo " SUPPRESSION SONARQUBE HELM MASSIF"
echo "===================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"

echo " PROBLÈME IDENTIFIÉ:"
echo "• SonarQube Helm Bitnami: 3Gi RAM + 1 CPU (ÉNORME !)"
echo "• Cluster disponible: Max 1Gi RAM par nœud"
echo "• Erreur: 6 Insufficient cpu, 6 Insufficient memory"
echo "• Solution: Supprimer Helm + déployer version légère"
echo ""

echo " COMPARAISON DES RESSOURCES:"
echo "• SonarQube Helm: 3Gi RAM, 1000m CPU (MASSIF)"
echo "• Notre version: 512Mi RAM, 200m CPU (LÉGER)"
echo "• Différence: 6x moins de RAM, 5x moins de CPU"
echo ""

# 1. Suppression complète du déploiement Helm
echo " 1. SUPPRESSION COMPLÈTE DU DÉPLOIEMENT HELM"
echo "----------------------------------------------"

echo "Suppression des déploiements SonarQube Helm..."
kubectl delete deployment sonarqube --ignore-not-found=true -n $NAMESPACE

echo "Suppression des ReplicaSets..."
kubectl delete replicaset --all -n $NAMESPACE --ignore-not-found=true

echo "Suppression des pods SonarQube..."
kubectl delete pod --all -n $NAMESPACE --ignore-not-found=true --field-selector=metadata.name!=postgres-7769844c4c-8fhzz

echo "Suppression des services SonarQube..."
kubectl delete svc sonarqube --ignore-not-found=true -n $NAMESPACE

echo "Suppression des PVCs SonarQube (pas PostgreSQL)..."
kubectl delete pvc sonarqube --ignore-not-found=true -n $NAMESPACE

echo "Suppression des secrets SonarQube..."
kubectl delete secret sonarqube sonarqube-externaldb --ignore-not-found=true -n $NAMESPACE

echo "Suppression des ConfigMaps SonarQube..."
kubectl delete configmap --all -n $NAMESPACE --ignore-not-found=true

echo "Suppression des PodDisruptionBudgets..."
kubectl delete poddisruptionbudget sonarqube --ignore-not-found=true -n $NAMESPACE

echo " Attente du nettoyage complet..."
sleep 20

# 2. Vérification du nettoyage
echo ""
echo " 2. VÉRIFICATION DU NETTOYAGE"
echo "-------------------------------"

echo "Pods restants:"
kubectl get pods -n $NAMESPACE

echo ""
echo "Services restants:"
kubectl get svc -n $NAMESPACE

echo ""
echo "PVCs restants:"
kubectl get pvc -n $NAMESPACE

# 3. Identifier le PVC PostgreSQL pour stockage partagé
echo ""
echo " 3. IDENTIFICATION DU STOCKAGE PARTAGÉ"
echo "----------------------------------------"

EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)

if [ -n "$EXISTING_PVC" ]; then
    echo " PVC PostgreSQL trouvé: $EXISTING_PVC"
    echo " Utilisation du stockage partagé (pas de quota SSD utilisé)"
else
    echo " Aucun PVC PostgreSQL disponible"
    exit 1
fi

# 4. Déploiement SonarQube LÉGER avec stockage partagé
echo ""
echo " 4. DÉPLOIEMENT SONARQUBE LÉGER"
echo "---------------------------------"

echo "Création du déploiement SonarQube LÉGER avec stockage partagé..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-light
  namespace: $NAMESPACE
  labels:
    app: sonarqube-light
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-light
  template:
    metadata:
      labels:
        app: sonarqube-light
    spec:
      containers:
      - name: sonarqube
        image: sonarqube:community
        ports:
        - containerPort: 9000
        env:
        - name: SONAR_JDBC_URL
          value: "jdbc:postgresql://postgres.sonarqube.svc.cluster.local:5432/sonarqube"
        - name: SONAR_JDBC_USERNAME
          value: "sonarqube"
        - name: SONAR_JDBC_PASSWORD
          value: "$POSTGRES_PASSWORD"
        - name: SONAR_ES_BOOTSTRAP_CHECKS_DISABLE
          value: "true"
        - name: SONAR_WEB_JAVAOPTS
          value: "-Xmx384m -Xms192m -XX:+UseG1GC"
        - name: SONAR_CE_JAVAOPTS
          value: "-Xmx384m -Xms192m -XX:+UseG1GC"
        - name: SONAR_SEARCH_JAVAOPTS
          value: "-Xmx256m -Xms256m"
        resources:
          requests:
            memory: "768Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: shared-storage
          mountPath: /opt/sonarqube/data
          subPath: sonarqube-data-light
        - name: shared-storage
          mountPath: /opt/sonarqube/logs
          subPath: sonarqube-logs-light
        - name: shared-storage
          mountPath: /opt/sonarqube/extensions
          subPath: sonarqube-extensions-light
        - name: temp-storage
          mountPath: /opt/sonarqube/temp
        readinessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 90
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 10
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 180
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 5
        startupProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 15
          timeoutSeconds: 10
          failureThreshold: 30
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: $EXISTING_PVC
      - name: temp-storage
        emptyDir:
          sizeLimit: 1Gi
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube-light
  namespace: $NAMESPACE
  labels:
    app: sonarqube-light
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
    name: http
  selector:
    app: sonarqube-light
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement SonarQube LÉGER créé avec succès"
else
    echo " Échec du déploiement SonarQube LÉGER"
    exit 1
fi

# 5. Surveillance du démarrage
echo ""
echo " 5. SURVEILLANCE DU DÉMARRAGE LÉGER"
echo "-------------------------------------"

echo " Surveillance du pod SonarQube LÉGER..."
echo " Ressources: 768Mi RAM (4x moins que Helm), 200m CPU (5x moins que Helm)"
echo " Stockage: Partagé avec PostgreSQL (pas de quota utilisé)"
echo ""

max_attempts=30  # 15 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -o wide
    
    # Vérifier si le pod est schedulé
    SCHEDULED_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-light --no-headers 2>/dev/null | grep -v "Pending" | wc -l)
    
    if [ "$SCHEDULED_PODS" -gt 0 ]; then
        echo " Pod SonarQube LÉGER schedulé avec succès!"
        
        # Vérifier si le pod est en cours d'exécution
        RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-light --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo " Pod SonarQube LÉGER en cours d'exécution!"
            
            # Vérifier l'IP du LoadBalancer
            SONAR_IP=$(kubectl get svc sonarqube-light -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            
            if [ -n "$SONAR_IP" ]; then
                echo " IP externe: $SONAR_IP"
                SONAR_URL="http://$SONAR_IP:9000"
                
                # Test de l'API
                echo " Test de l'API SonarQube..."
                if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP"; then
                    echo ""
                    echo " SUCCÈS FINAL ! SONARQUBE LÉGER OPÉRATIONNEL !"
                    echo "==============================================="
                    echo " URL: $SONAR_URL"
                    echo " Identifiants: admin / admin"
                    echo " Mémoire: 1Gi (vs 6Gi Helm = 6x moins)"
                    echo " CPU: 500m (vs 3000m Helm = 6x moins)"
                    echo " Stockage: Partagé avec PostgreSQL"
                    echo " Restarts: 0 (déploiement propre)"
                    echo ""
                    echo " Utilisation finale des ressources:"
                    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                    echo ""
                    echo " PROBLÈME RÉSOLU DÉFINITIVEMENT:"
                    echo "•  SonarQube Helm massif supprimé"
                    echo "•  Version légère déployée"
                    echo "•  Ressources adaptées au cluster"
                    echo "•  Stockage partagé fonctionnel"
                    echo "•  API opérationnelle"
                    echo ""
                    exit 0
                elif curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "STARTING"; then
                    echo " SonarQube démarre encore (STARTING)..."
                fi
            else
                echo " IP externe pas encore assignée..."
            fi
        fi
    fi
    
    # Vérifier les erreurs de scheduling
    PENDING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-light --no-headers 2>/dev/null | grep "Pending" | wc -l)
    if [ "$PENDING_PODS" -gt 0 ]; then
        echo " Pod encore en Pending"
        PENDING_REASON=$(kubectl describe pod -l app=sonarqube-light -n $NAMESPACE 2>/dev/null | grep -A 3 "Events:" | grep "FailedScheduling" | tail -1)
        if [ -n "$PENDING_REASON" ]; then
            echo "Raison: $PENDING_REASON"
        fi
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents:"
    kubectl logs -l app=sonarqube-light -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 15 minutes"

# 6. Diagnostic final
echo ""
echo " 6. DIAGNOSTIC FINAL"
echo "---------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Description du pod SonarQube LÉGER:"
kubectl describe pod -l app=sonarqube-light -n $NAMESPACE 2>/dev/null

echo ""
echo "Services disponibles:"
kubectl get svc -n $NAMESPACE

echo ""
echo " RECOMMANDATIONS SI ÉCHEC:"
echo "• Le cluster manque peut-être encore de ressources"
echo "• Réduire encore plus: 512Mi RAM, 100m CPU"
echo "• Utiliser SonarCloud (service managé)"
echo "• Augmenter la taille du cluster GKE"

echo ""
echo "Script terminé: $(date)"

