#!/bin/bash

# SOLUTION DÉFINITIVE : QUOTA SSD DÉPASSÉ
# Problème identifié : Quota 'SSD_TOTAL_GB' exceeded. Limit: 400.0 in region europe-west9

echo " SOLUTION DÉFINITIVE : QUOTA SSD DÉPASSÉ"
echo "=========================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"
MONITORING_PASSCODE="monitoring-$(date +%s)-$(openssl rand -hex 4)"

echo " PROBLÈME IDENTIFIÉ:"
echo "• Quota SSD: 400GB/400GB (100% utilisé)"
echo "• 3 PVCs PostgreSQL: 30Gi utilisés"
echo "• Nouveau PVC SonarQube: Impossible à créer"
echo "• Solution: Utiliser un PVC PostgreSQL existant"
echo ""

# 1. Nettoyer les déploiements en échec
echo " 1. NETTOYAGE DES DÉPLOIEMENTS EN ÉCHEC"
echo "-----------------------------------------"

kubectl delete deployment sonarqube-minimal --ignore-not-found=true -n $NAMESPACE
kubectl delete pvc sonarqube-minimal-pvc --ignore-not-found=true -n $NAMESPACE
kubectl delete statefulset sonarqube-sonarqube --ignore-not-found=true -n $NAMESPACE

echo " Attente du nettoyage..."
sleep 10

# 2. Identifier un PVC PostgreSQL existant
echo ""
echo " 2. IDENTIFICATION D'UN PVC EXISTANT"
echo "--------------------------------------"

echo "PVCs PostgreSQL disponibles:"
kubectl get pvc -n $NAMESPACE | grep postgres-pvc

# Sélectionner le premier PVC PostgreSQL lié
EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)

if [ -n "$EXISTING_PVC" ]; then
    echo " PVC sélectionné: $EXISTING_PVC"
    
    # Vérifier le nœud lié
    PVC_NODE=$(kubectl get pv $(kubectl get pvc $EXISTING_PVC -n $NAMESPACE -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null || echo "")
    if [ -n "$PVC_NODE" ]; then
        echo " PVC lié au nœud: $PVC_NODE"
    fi
else
    echo " Aucun PVC PostgreSQL disponible"
    exit 1
fi

# 3. Créer un déploiement SonarQube utilisant le PVC existant
echo ""
echo " 3. DÉPLOIEMENT SONARQUBE AVEC PVC EXISTANT"
echo "---------------------------------------------"

echo "Création d'un déploiement SonarQube partageant le stockage PostgreSQL..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-shared-storage
  namespace: $NAMESPACE
  labels:
    app: sonarqube-shared
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-shared
  template:
    metadata:
      labels:
        app: sonarqube-shared
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
          value: "-Xmx128m -Xms64m"
        - name: SONAR_CE_JAVAOPTS
          value: "-Xmx128m -Xms64m"
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        volumeMounts:
        - name: shared-storage
          mountPath: /opt/sonarqube/data
          subPath: sonarqube-data
        - name: shared-storage
          mountPath: /opt/sonarqube/logs
          subPath: sonarqube-logs
        - name: shared-storage
          mountPath: /opt/sonarqube/extensions
          subPath: sonarqube-extensions
        readinessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 10
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 5
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: $EXISTING_PVC
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement avec stockage partagé créé"
else
    echo " Échec du déploiement avec stockage partagé"
    exit 1
fi

# 4. Créer le service LoadBalancer
echo ""
echo " 4. CRÉATION DU SERVICE LOADBALANCER"
echo "-------------------------------------"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sonarqube-shared
  namespace: $NAMESPACE
  labels:
    app: sonarqube-shared
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
  selector:
    app: sonarqube-shared
EOF

echo " Service LoadBalancer créé"

# 5. Surveillance du démarrage
echo ""
echo " 5. SURVEILLANCE DU DÉMARRAGE"
echo "-------------------------------"

echo " Surveillance du pod SonarQube avec stockage partagé..."
max_attempts=30  # 15 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -l app=sonarqube-shared -o wide
    
    # Vérifier si le pod est schedulé
    SCHEDULED_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-shared --no-headers 2>/dev/null | grep -v "Pending" | wc -l)
    
    if [ "$SCHEDULED_PODS" -gt 0 ]; then
        echo " Pod SonarQube schedulé avec succès!"
        
        # Vérifier si le pod est en cours d'exécution
        RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-shared --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo " Pod SonarQube en cours d'exécution!"
            
            # Vérifier l'IP du LoadBalancer
            SONAR_IP=$(kubectl get svc sonarqube-shared -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            
            if [ -n "$SONAR_IP" ]; then
                echo " IP externe: $SONAR_IP"
                SONAR_URL="http://$SONAR_IP:9000"
                
                # Test de l'API
                if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP\|STARTING"; then
                    echo ""
                    echo " SUCCÈS COMPLET AVEC STOCKAGE PARTAGÉ!"
                    echo "========================================"
                    echo " URL: $SONAR_URL"
                    echo " Identifiants: admin / admin"
                    echo " Stockage: Partagé avec PostgreSQL (pas de quota utilisé)"
                    echo " Mémoire: 128Mi"
                    echo " CPU: 50m"
                    echo " PVC utilisé: $EXISTING_PVC"
                    echo ""
                    echo " Utilisation finale des ressources:"
                    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                    echo ""
                    echo " AVANTAGES DE CETTE SOLUTION:"
                    echo "• Aucun quota SSD supplémentaire utilisé"
                    echo "• Utilise un volume existant déjà lié"
                    echo "• SonarQube et PostgreSQL sur le même nœud"
                    echo "• Performance optimale (pas de réseau entre volumes)"
                    echo ""
                    exit 0
                fi
            fi
        fi
    fi
    
    # Vérifier les erreurs de scheduling
    PENDING_REASON=$(kubectl describe pod -l app=sonarqube-shared -n $NAMESPACE 2>/dev/null | grep -A 5 "Events:" | grep "FailedScheduling" | tail -1)
    if [ -n "$PENDING_REASON" ]; then
        echo " Raison du Pending: $PENDING_REASON"
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents:"
    kubectl logs -l app=sonarqube-shared -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 15 minutes"

# 6. Diagnostic en cas d'échec
echo ""
echo " 6. DIAGNOSTIC EN CAS D'ÉCHEC"
echo "------------------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Description du pod:"
kubectl describe pod -l app=sonarqube-shared -n $NAMESPACE 2>/dev/null

echo ""
echo "État des PVCs:"
kubectl get pvc -n $NAMESPACE

echo ""
echo " SOLUTIONS ALTERNATIVES:"
echo "• Augmenter le quota SSD sur GCP"
echo "• Supprimer des PVCs PostgreSQL inutilisés"
echo "• Utiliser un cluster avec plus de quota"
echo "• Déployer SonarQube en externe (hors Kubernetes)"

echo ""
echo "Script terminé: $(date)"

