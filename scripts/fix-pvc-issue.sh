#!/bin/bash

# Script de correction pour le problème de PVC PostgreSQL
# Le PVC existant ne peut pas être réduit de 10Gi à 5Gi

set -e

NAMESPACE="sonarqube"

echo " CORRECTION DU PROBLÈME PVC POSTGRESQL"
echo "========================================"

echo ""
echo "=== PROBLÈME IDENTIFIÉ ==="
echo "Le PVC postgres-pv-claim existe déjà avec 10Gi"
echo "On ne peut pas réduire un PVC existant de 10Gi à 5Gi"

echo ""
echo "=== SOLUTION : GARDER LE PVC EXISTANT ==="

# 1. Supprimer le deployment PostgreSQL qui a échoué
echo "Suppression du deployment PostgreSQL en erreur..."
kubectl delete deployment postgres -n $NAMESPACE --ignore-not-found=true

# 2. Créer un manifeste PostgreSQL qui utilise le PVC existant de 10Gi
echo "Création du manifeste PostgreSQL avec PVC existant..."

cat > /tmp/postgres-fixed.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: sonarqube
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:13
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_DB
          value: sonarqube
        - name: POSTGRES_USER
          value: sonarqube
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            cpu: "100m"      # Ressources réduites
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U sonarqube -d sonarqube -h localhost
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U sonarqube -d sonarqube -h localhost
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        startupProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U sonarqube -d sonarqube -h localhost
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 20
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pv-claim  # Utilise le PVC existant
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
EOF

# 3. Appliquer le manifeste corrigé
echo "Application du manifeste PostgreSQL corrigé..."
kubectl apply -f /tmp/postgres-fixed.yaml

# 4. Attendre que PostgreSQL démarre
echo "Attente du démarrage de PostgreSQL..."
kubectl wait --for=condition=available deployment/postgres -n $NAMESPACE --timeout=300s

# 5. Vérifier PostgreSQL
echo ""
echo "=== VÉRIFICATION POSTGRESQL ==="
kubectl get pods -n $NAMESPACE -l app=postgres

echo "Test de connexion PostgreSQL..."
kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U sonarqube -d sonarqube -h localhost

# 6. Déployer SonarQube avec le PVC existant aussi
echo ""
echo "=== DÉPLOIEMENT SONARQUBE ==="

cat > /tmp/sonarqube-fixed.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube
  namespace: sonarqube
  labels:
    app: sonarqube
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube
  template:
    metadata:
      labels:
        app: sonarqube
    spec:
      initContainers:
      - name: init-sysctl
        image: busybox:1.35
        command:
        - /bin/sh
        - -c
        - |
          sysctl -w vm.max_map_count=262144
          sysctl -w fs.file-max=65536
        securityContext:
          privileged: true
      containers:
      - name: sonarqube
        image: sonarqube:community
        ports:
        - containerPort: 9000
          name: http
        env:
        - name: SONAR_JDBC_URL
          value: "jdbc:postgresql://postgres:5432/sonarqube"
        - name: SONAR_JDBC_USERNAME
          value: "sonarqube"
        - name: SONAR_JDBC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
        - name: SONAR_ES_BOOTSTRAP_CHECKS_DISABLE
          value: "true"
        - name: SONAR_WEB_JAVAADDITIONALOPTS
          value: "-Xmx512m -Xms128m"
        - name: SONAR_CE_JAVAADDITIONALOPTS
          value: "-Xmx256m -Xms64m"
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
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
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30
      volumes:
      - name: sonarqube-data
        persistentVolumeClaim:
          claimName: sonarqube  # Utilise le PVC existant
      - name: sonarqube-logs
        emptyDir: {}
      - name: sonarqube-extensions
        emptyDir: {}
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
EOF

kubectl apply -f /tmp/sonarqube-fixed.yaml

echo "Attente du démarrage de SonarQube (cela peut prendre plusieurs minutes)..."
kubectl wait --for=condition=available deployment/sonarqube -n $NAMESPACE --timeout=600s

# 7. Vérification finale
echo ""
echo "=== VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 8. Informations d'accès
echo ""
echo " INFORMATIONS D'ACCÈS"
echo "======================="

SONARQUBE_IP=$(kubectl get svc sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "En cours d'attribution...")

if [ "$SONARQUBE_IP" != "En cours d'attribution..." ] && [ -n "$SONARQUBE_IP" ]; then
    echo " SonarQube accessible à : http://$SONARQUBE_IP:9000"
else
    echo " IP externe en cours d'attribution. Vérifiez avec :"
    echo "   kubectl get svc sonarqube -n $NAMESPACE"
    echo ""
    echo " Accès local via port-forward :"
    echo "   kubectl port-forward -n $NAMESPACE svc/sonarqube 9000:9000"
    echo "   Puis ouvrir : http://localhost:9000"
fi

echo ""
echo " Identifiants par défaut :"
echo "   Utilisateur : admin"
echo "   Mot de passe : admin"

echo ""
echo " CORRECTION TERMINÉE AVEC SUCCÈS !"
echo "===================================="

# Nettoyage des fichiers temporaires
rm -f /tmp/postgres-fixed.yaml /tmp/sonarqube-fixed.yaml
