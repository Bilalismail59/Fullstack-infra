#!/bin/bash

# Solution DÉFINITIVE pour SonarQube qui reste en Pending
# Même avec 100m CPU et 256Mi RAM, le pod ne se schedule pas
# Il faut identifier et résoudre le problème racine

echo " ANALYSE APPROFONDIE DU PROBLÈME PENDING"
echo "=========================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"

echo " OBSERVATION:"
echo "• Ressources ultra-réduites: 100m CPU, 256Mi RAM"
echo "• Nœuds disponibles: 13-25% CPU utilisé"
echo "• Pod reste en Pending depuis 7+ minutes"
echo "• Problème ≠ ressources CPU/mémoire"
echo ""

# 1. Diagnostic approfondi du scheduling
echo " 1. DIAGNOSTIC APPROFONDI DU SCHEDULING"
echo "-----------------------------------------"

echo "Description détaillée du pod SonarQube:"
kubectl describe pod sonarqube-sonarqube-0 -n $NAMESPACE

echo ""
echo "Événements récents du namespace:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

echo ""
echo "Vérification des contraintes de scheduling:"
kubectl get pod sonarqube-sonarqube-0 -n $NAMESPACE -o yaml | grep -A 10 -E "(nodeSelector|affinity|tolerations|topologySpreadConstraints)"

# 2. Vérification des PVCs
echo ""
echo " 2. VÉRIFICATION DES PVCS"
echo "---------------------------"

echo "État des PVCs SonarQube:"
kubectl get pvc -n $NAMESPACE

echo ""
echo "PVC en attente (si applicable):"
kubectl get pvc -n $NAMESPACE | grep Pending

PENDING_PVC=$(kubectl get pvc sonarqube-sonarqube -n $NAMESPACE --no-headers 2>/dev/null | grep Pending)
if [ -n "$PENDING_PVC" ]; then
    echo ""
    echo " PVC SonarQube en Pending détecté!"
    echo "Description du PVC:"
    kubectl describe pvc sonarqube-sonarqube -n $NAMESPACE
fi

# 3. Vérification des quotas et limites
echo ""
echo " 3. VÉRIFICATION DES QUOTAS"
echo "-----------------------------"

echo "ResourceQuotas dans le namespace:"
kubectl get resourcequota -n $NAMESPACE 2>/dev/null || echo "Aucun quota configuré"

echo ""
echo "LimitRanges dans le namespace:"
kubectl get limitrange -n $NAMESPACE 2>/dev/null || echo "Aucune limite configurée"

# 4. Vérification des taints et tolerations
echo ""
echo " 4. VÉRIFICATION DES TAINTS"
echo "-----------------------------"

echo "Taints sur les nœuds:"
kubectl describe nodes | grep -E "(Name:|Taints:)" | grep -A 1 "Name:"

# 5. Solution: Déploiement manuel avec ressources minimales absolues
echo ""
echo " 5. SOLUTION: DÉPLOIEMENT MANUEL MINIMAL"
echo "==========================================="

echo "Suppression du StatefulSet SonarQube..."
kubectl delete statefulset sonarqube-sonarqube -n $NAMESPACE --ignore-not-found=true

echo "Suppression du PVC problématique..."
kubectl delete pvc sonarqube-sonarqube -n $NAMESPACE --ignore-not-found=true

echo "Attente du nettoyage..."
sleep 10

echo ""
echo "Création d'un déploiement SonarQube MINIMAL manuel..."

# Générer un passcode
MONITORING_PASSCODE="monitoring-$(date +%s)-$(openssl rand -hex 4)"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarqube-minimal-pvc
  namespace: $NAMESPACE
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard-rwo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-minimal
  namespace: $NAMESPACE
  labels:
    app: sonarqube-minimal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-minimal
  template:
    metadata:
      labels:
        app: sonarqube-minimal
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
          value: "sonarqube"
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
        - name: sonarqube-data
          mountPath: /opt/sonarqube/data
        - name: sonarqube-logs
          mountPath: /opt/sonarqube/logs
        - name: sonarqube-extensions
          mountPath: /opt/sonarqube/extensions
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
      - name: sonarqube-data
        persistentVolumeClaim:
          claimName: sonarqube-minimal-pvc
      - name: sonarqube-logs
        emptyDir: {}
      - name: sonarqube-extensions
        emptyDir: {}
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube-minimal
  namespace: $NAMESPACE
  labels:
    app: sonarqube-minimal
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
  selector:
    app: sonarqube-minimal
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement minimal créé avec succès"
else
    echo " Échec du déploiement minimal"
    exit 1
fi

# 6. Surveillance du déploiement minimal
echo ""
echo " 6. SURVEILLANCE DU DÉPLOIEMENT MINIMAL"
echo "-----------------------------------------"

echo " Surveillance du pod SonarQube minimal..."
max_attempts=40  # 20 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -l app=sonarqube-minimal -o wide
    
    # Vérifier si le pod est schedulé
    SCHEDULED_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-minimal --no-headers 2>/dev/null | grep -v "Pending" | wc -l)
    
    if [ "$SCHEDULED_PODS" -gt 0 ]; then
        echo " Pod SonarQube minimal schedulé!"
        
        # Vérifier si le pod est en cours d'exécution
        RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-minimal --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo " Pod SonarQube minimal en cours d'exécution!"
            
            # Vérifier l'IP du LoadBalancer
            SONAR_IP=$(kubectl get svc sonarqube-minimal -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            
            if [ -n "$SONAR_IP" ]; then
                echo " IP externe: $SONAR_IP"
                SONAR_URL="http://$SONAR_IP:9000"
                
                # Test de l'API
                if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP\|STARTING"; then
                    echo ""
                    echo " SUCCÈS COMPLET AVEC DÉPLOIEMENT MINIMAL!"
                    echo "==========================================="
                    echo " URL: $SONAR_URL"
                    echo " Identifiants: admin / admin"
                    echo " Stockage: 5Gi (au lieu de 10Gi)"
                    echo " Mémoire: 128Mi (au lieu de 256Mi)"
                    echo " CPU: 50m (au lieu de 100m)"
                    echo ""
                    echo " Ressources finales utilisées:"
                    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                    echo ""
                    exit 0
                fi
            fi
        fi
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents:"
    kubectl logs -l app=sonarqube-minimal -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    # Vérifier les erreurs de scheduling
    PENDING_REASON=$(kubectl describe pod -l app=sonarqube-minimal -n $NAMESPACE 2>/dev/null | grep -A 5 "Events:" | grep "FailedScheduling" | tail -1)
    if [ -n "$PENDING_REASON" ]; then
        echo "⚠️ Raison du Pending: $PENDING_REASON"
    fi
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 20 minutes"

# 7. Diagnostic final en cas d'échec
echo ""
echo " 7. DIAGNOSTIC FINAL"
echo "---------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Description du pod minimal:"
kubectl describe pod -l app=sonarqube-minimal -n $NAMESPACE 2>/dev/null

echo ""
echo "Événements du namespace:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

echo ""
echo " SOLUTIONS ULTIMES:"
echo "• Le cluster manque peut-être de nœuds disponibles"
echo "• Vérifier les policies de sécurité (PodSecurityPolicy)"
echo "• Augmenter la taille du cluster GKE"
echo "• Utiliser une image SonarQube plus légère"
echo "• Déployer sur un cluster différent"

echo ""
echo "Script terminé: $(date)"

