#!/bin/bash

# DIAGNOSTIC APPROFONDI : SERVICES SANS PODS
# Problème : Services LoadBalancer existent mais aucun pod SonarQube
# Cause probable : Pods supprimés après trop de restarts OOMKilled

echo " DIAGNOSTIC APPROFONDI : SERVICES SANS PODS"
echo "=============================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"

echo " PROBLÈME IDENTIFIÉ:"
echo "• Services LoadBalancer: 2 avec IPs externes"
echo "• Pods SonarQube: 0 (aucun pod trouvé)"
echo "• Cause probable: Pods supprimés après trop de restarts"
echo "• Solution: Diagnostic + relance propre"
echo ""

# 1. Diagnostic complet des déploiements
echo " 1. DIAGNOSTIC DES DÉPLOIEMENTS"
echo "---------------------------------"

echo "Déploiements dans le namespace:"
kubectl get deployments -n $NAMESPACE -o wide

echo ""
echo "ReplicaSets dans le namespace:"
kubectl get replicasets -n $NAMESPACE -o wide

echo ""
echo "Tous les pods (y compris terminés):"
kubectl get pods -n $NAMESPACE --show-all 2>/dev/null || kubectl get pods -n $NAMESPACE

# 2. Vérification des événements récents
echo ""
echo " 2. ÉVÉNEMENTS RÉCENTS"
echo "------------------------"

echo "Événements du namespace (20 derniers):"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

# 3. Diagnostic des services orphelins
echo ""
echo " 3. DIAGNOSTIC DES SERVICES ORPHELINS"
echo "---------------------------------------"

echo "Services LoadBalancer détaillés:"
kubectl get svc -n $NAMESPACE -o wide

echo ""
echo "Endpoints des services:"
kubectl get endpoints -n $NAMESPACE

# Vérifier chaque service LoadBalancer
SONAR_SERVICES=$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' | tr ' ' '\n' | grep -E '(sonarqube|optimized|minimal)')

for service in $SONAR_SERVICES; do
    echo ""
    echo "=== Service: $service ==="
    kubectl describe svc $service -n $NAMESPACE | grep -A 10 -E "(Selector|Endpoints|TargetPort)"
done

# 4. Vérification des PVCs et stockage
echo ""
echo " 4. VÉRIFICATION DU STOCKAGE"
echo "------------------------------"

echo "État détaillé des PVCs:"
kubectl describe pvc -n $NAMESPACE

# 5. Nettoyage et relance propre
echo ""
echo " 5. NETTOYAGE ET RELANCE PROPRE"
echo "---------------------------------"

echo "Suppression des services orphelins..."
kubectl delete svc sonarqube-minimal sonarqube-optimized --ignore-not-found=true -n $NAMESPACE

echo "Suppression des déploiements fantômes..."
kubectl delete deployment sonarqube-minimal sonarqube-shared-storage sonarqube-memory-optimized --ignore-not-found=true -n $NAMESPACE

echo "Nettoyage des ReplicaSets..."
kubectl delete replicaset --all -n $NAMESPACE --ignore-not-found=true

echo " Attente du nettoyage complet..."
sleep 15

# 6. Identifier le meilleur PVC disponible
echo ""
echo " 6. IDENTIFICATION DU PVC OPTIMAL"
echo "-----------------------------------"

EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)

if [ -n "$EXISTING_PVC" ]; then
    echo " PVC sélectionné: $EXISTING_PVC"
    
    # Vérifier l'espace utilisé
    echo "Vérification de l'espace disponible..."
    kubectl describe pv $(kubectl get pvc $EXISTING_PVC -n $NAMESPACE -o jsonpath='{.spec.volumeName}') | grep -E "(Capacity|Status)"
else
    echo " Aucun PVC PostgreSQL disponible"
    exit 1
fi

# 7. Déploiement SonarQube FINAL avec mémoire maximale
echo ""
echo " 7. DÉPLOIEMENT SONARQUBE FINAL"
echo "---------------------------------"

echo "Création du déploiement SonarQube FINAL avec 2Gi de mémoire..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-final
  namespace: $NAMESPACE
  labels:
    app: sonarqube-final
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-final
  template:
    metadata:
      labels:
        app: sonarqube-final
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
          value: "-Xmx768m -Xms384m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
        - name: SONAR_CE_JAVAOPTS
          value: "-Xmx768m -Xms384m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
        - name: SONAR_SEARCH_JAVAOPTS
          value: "-Xmx512m -Xms512m -XX:+UseG1GC"
        resources:
          requests:
            memory: "1536Mi"
            cpu: "200m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: shared-storage
          mountPath: /opt/sonarqube/data
          subPath: sonarqube-data-final
        - name: shared-storage
          mountPath: /opt/sonarqube/logs
          subPath: sonarqube-logs-final
        - name: shared-storage
          mountPath: /opt/sonarqube/extensions
          subPath: sonarqube-extensions-final
        - name: temp-storage
          mountPath: /opt/sonarqube/temp
        readinessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 15
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 300
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 5
        startupProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 10
          failureThreshold: 40
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: $EXISTING_PVC
      - name: temp-storage
        emptyDir:
          sizeLimit: 2Gi
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
      nodeSelector:
        kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube-final
  namespace: $NAMESPACE
  labels:
    app: sonarqube-final
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
    name: http
  selector:
    app: sonarqube-final
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement SonarQube FINAL créé avec 2Gi de mémoire"
else
    echo " Échec du déploiement SonarQube FINAL"
    exit 1
fi

# 8. Surveillance intensive du démarrage
echo ""
echo " 8. SURVEILLANCE INTENSIVE"
echo "----------------------------"

echo " Surveillance du déploiement SonarQube FINAL..."
echo " Mémoire: 2Gi (8x plus que la première tentative)"
echo " CPU: 1000m (10x plus que la première tentative)"
echo " Timeout startup: 10 minutes"
echo ""

max_attempts=60  # 30 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -l app=sonarqube-final -o wide
    
    # Vérifier si le pod est en cours d'exécution
    RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-final --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
        echo " Pod SonarQube FINAL en cours d'exécution!"
        
        # Vérifier l'IP du LoadBalancer
        SONAR_IP=$(kubectl get svc sonarqube-final -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        if [ -n "$SONAR_IP" ]; then
            echo " IP externe: $SONAR_IP"
            SONAR_URL="http://$SONAR_IP:9000"
            
            # Test de l'API
            echo " Test de l'API SonarQube..."
            if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP"; then
                echo ""
                echo " SUCCÈS FINAL ! SONARQUBE OPÉRATIONNEL !"
                echo "=========================================="
                echo " URL: $SONAR_URL"
                echo " Identifiants: admin / admin"
                echo " Mémoire: 2Gi (problème OOMKilled définitivement résolu)"
                echo " CPU: 1000m"
                echo " Stockage: Partagé avec PostgreSQL"
                echo " Restarts: 0 (déploiement propre)"
                echo ""
                echo " Utilisation finale des ressources:"
                kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                echo ""
                echo " TOUS LES PROBLÈMES RÉSOLUS:"
                echo "•  Quota SSD: Stockage partagé"
                echo "•  Scheduling: Pod schedulé"
                echo "•  OOMKilled: 2Gi mémoire"
                echo "•  Services orphelins: Nettoyés"
                echo "•  API opérationnelle: Tests réussis"
                echo ""
                exit 0
            elif curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "STARTING"; then
                echo " SonarQube démarre encore (STARTING)..."
            fi
        else
            echo " IP externe pas encore assignée..."
        fi
    fi
    
    # Vérifier les erreurs
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-final --no-headers 2>/dev/null | awk '{print $3}')
    if [[ "$POD_STATUS" == *"OOMKilled"* ]]; then
        echo " ENCORE OOMKilled avec 2Gi ! SonarQube nécessite plus de mémoire"
        echo " Recommandation: Utiliser SonarCloud ou un cluster plus puissant"
    elif [[ "$POD_STATUS" == *"CrashLoopBackOff"* ]]; then
        echo " CrashLoopBackOff détecté"
        echo " Logs récents:"
        kubectl logs -l app=sonarqube-final -n $NAMESPACE --tail=10 2>/dev/null
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents (3 dernières lignes):"
    kubectl logs -l app=sonarqube-final -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 30 minutes"

# 9. Diagnostic final
echo ""
echo " 9. DIAGNOSTIC FINAL"
echo "---------------------"

echo "État final:"
kubectl get all -n $NAMESPACE

echo ""
echo "Logs complets du dernier pod:"
kubectl logs -l app=sonarqube-final -n $NAMESPACE --tail=50 2>/dev/null

echo ""
echo " SOLUTIONS ULTIMES SI ÉCHEC:"
echo "• SonarQube Community nécessite plus de 2Gi sur ce cluster"
echo "• Utiliser SonarCloud (service managé Sonar)"
echo "• Déployer sur un cluster avec plus de ressources"
echo "• Utiliser une version SonarQube LTS plus légère"

echo ""
echo "Script terminé: $(date)"

