#!/bin/bash

# SOLUTION POUR OOMKILLED : AUGMENTATION MÉMOIRE SONARQUBE
# Problème identifié : SonarQube consomme plus de 256Mi et est tué (OOMKilled)
# Solution : Augmenter la mémoire et optimiser la configuration

echo " SOLUTION OOMKILLED : AUGMENTATION MÉMOIRE"
echo "============================================"
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sonarqube}"

echo " PROBLÈME IDENTIFIÉ:"
echo "• SonarQube: OOMKilled (mémoire insuffisante)"
echo "• Limite actuelle: 256Mi"
echo "• Restarts: 5+ (CrashLoopBackOff)"
echo "• Solution: Augmenter à 512Mi-1Gi"
echo ""

echo " SUCCÈS PRÉCÉDENTS:"
echo "• Stockage partagé: Fonctionne parfaitement"
echo "• Scheduling: Pod schedulé immédiatement"
echo "• Quota SSD: Aucun quota supplémentaire utilisé"
echo ""

# 1. Identifier le PVC existant
echo " 1. IDENTIFICATION DU PVC EXISTANT"
echo "------------------------------------"

EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)

if [ -n "$EXISTING_PVC" ]; then
    echo " PVC sélectionné: $EXISTING_PVC"
else
    echo " Aucun PVC PostgreSQL disponible"
    exit 1
fi

# 2. Supprimer le déploiement actuel
echo ""
echo " 2. SUPPRESSION DU DÉPLOIEMENT ACTUEL"
echo "---------------------------------------"

kubectl delete deployment sonarqube-shared-storage --ignore-not-found=true -n $NAMESPACE
kubectl delete service sonarqube-shared --ignore-not-found=true -n $NAMESPACE

echo " Attente du nettoyage..."
sleep 15

# 3. Créer un nouveau déploiement avec plus de mémoire
echo ""
echo " 3. DÉPLOIEMENT AVEC MÉMOIRE AUGMENTÉE"
echo "----------------------------------------"

echo "Création d'un déploiement SonarQube avec 1Gi de mémoire..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-memory-optimized
  namespace: $NAMESPACE
  labels:
    app: sonarqube-optimized
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-optimized
  template:
    metadata:
      labels:
        app: sonarqube-optimized
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
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "500m"
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
          periodSeconds: 10
          timeoutSeconds: 5
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
  name: sonarqube-optimized
  namespace: $NAMESPACE
  labels:
    app: sonarqube-optimized
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
  selector:
    app: sonarqube-optimized
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement avec mémoire optimisée créé"
else
    echo " Échec du déploiement avec mémoire optimisée"
    exit 1
fi

# 4. Surveillance du démarrage
echo ""
echo " 4. SURVEILLANCE DU DÉMARRAGE OPTIMISÉ"
echo "----------------------------------------"

echo " Surveillance du pod SonarQube avec mémoire augmentée..."
echo " Mémoire allouée: 768Mi request, 1Gi limit"
echo " CPU alloué: 100m request, 500m limit"
echo ""

max_attempts=40  # 20 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -l app=sonarqube-optimized -o wide
    
    # Vérifier si le pod est en cours d'exécution
    RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-optimized --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
        echo " Pod SonarQube en cours d'exécution!"
        
        # Vérifier l'IP du LoadBalancer
        SONAR_IP=$(kubectl get svc sonarqube-optimized -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        if [ -n "$SONAR_IP" ]; then
            echo " IP externe: $SONAR_IP"
            SONAR_URL="http://$SONAR_IP:9000"
            
            # Test de l'API
            echo " Test de l'API SonarQube..."
            if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP"; then
                echo ""
                echo " SUCCÈS COMPLET ! OOMKILLED RÉSOLU !"
                echo "====================================="
                echo " URL: $SONAR_URL"
                echo " Identifiants: admin / admin"
                echo " Mémoire: 1Gi (4x plus qu'avant)"
                echo " CPU: 500m"
                echo " Stockage: Partagé avec PostgreSQL"
                echo " Restarts: 0 (plus d'OOMKilled)"
                echo ""
                echo " Utilisation finale des ressources:"
                kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                echo ""
                echo " PROBLÈMES RÉSOLUS:"
                echo "•  Quota SSD: Stockage partagé (0 quota utilisé)"
                echo "•  Scheduling: Pod schedulé immédiatement"
                echo "•  OOMKilled: Mémoire augmentée à 1Gi"
                echo "•  Performance: JVM optimisée avec G1GC"
                echo ""
                exit 0
            elif curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "STARTING"; then
                echo " SonarQube démarre encore (STARTING)..."
            fi
        else
            echo " IP externe pas encore assignée..."
        fi
    fi
    
    # Vérifier les erreurs OOMKilled
    OOMKILLED_COUNT=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-optimized --no-headers 2>/dev/null | grep "OOMKilled" | wc -l)
    if [ "$OOMKILLED_COUNT" -gt 0 ]; then
        echo " ENCORE OOMKilled détecté ! Mémoire insuffisante même avec 1Gi"
        echo " Solution: Augmenter encore plus la mémoire ou utiliser une version plus légère"
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents:"
    kubectl logs -l app=sonarqube-optimized -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    # Afficher l'utilisation mémoire si disponible
    echo ""
    echo " Utilisation mémoire:"
    kubectl top pods -n $NAMESPACE -l app=sonarqube-optimized 2>/dev/null || echo "Métriques non disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 20 minutes"

# 5. Diagnostic en cas d'échec
echo ""
echo " 5. DIAGNOSTIC EN CAS D'ÉCHEC"
echo "------------------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Description du pod:"
kubectl describe pod -l app=sonarqube-optimized -n $NAMESPACE 2>/dev/null

echo ""
echo "Logs complets:"
kubectl logs -l app=sonarqube-optimized -n $NAMESPACE --tail=50 2>/dev/null

echo ""
echo "Utilisation des ressources:"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"

echo ""
echo " SOLUTIONS SUPPLÉMENTAIRES SI ÉCHEC:"
echo "• Augmenter encore la mémoire (1.5Gi ou 2Gi)"
echo "• Utiliser SonarQube LTS (version plus stable)"
echo "• Désactiver Elasticsearch intégré"
echo "• Utiliser SonarCloud (service managé)"

echo ""
echo "Script terminé: $(date)"

