#!/bin/bash

# Solution rapide pour le problème de quota SSD dépassé

NAMESPACE="sonarqube"

echo " SOLUTION QUOTA SSD DÉPASSÉ"
echo "=============================="

echo ""
echo " PROBLÈME IDENTIFIÉ:"
echo "Quota 'SSD_TOTAL_GB' exceeded. Limit: 400.0 in region europe-west9"

echo ""
echo " SOLUTION RAPIDE:"
echo "Utiliser le PVC existant 'postgres-pv-claim-new' qui est déjà lié!"

echo ""
echo "=== 1. VÉRIFICATION DES PVC DISPONIBLES ==="
kubectl get pvc -n $NAMESPACE

echo ""
echo "=== 2. SUPPRESSION DU PVC PROBLÉMATIQUE ==="
kubectl delete pvc postgres-pv-claim -n $NAMESPACE --ignore-not-found=true

echo ""
echo "=== 3. SUPPRESSION DU DEPLOYMENT POSTGRESQL EN ERREUR ==="
kubectl delete deployment postgres -n $NAMESPACE --ignore-not-found=true

echo "Attente du nettoyage..."
sleep 10

echo ""
echo "=== 4. DÉPLOIEMENT POSTGRESQL AVEC PVC EXISTANT ==="

cat > /tmp/postgres-with-existing-pvc.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: sonarqube
type: Opaque
data:
  postgres-password: c29uYXJxdWJl  # base64 de "sonarqube"
---
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
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "sonarqube", "-d", "sonarqube"]
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 6
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "sonarqube", "-d", "sonarqube"]
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        startupProbe:
          exec:
            command: ["pg_isready", "-U", "sonarqube", "-d", "sonarqube"]
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 20
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pv-claim-new  #  Utilise le PVC existant qui fonctionne
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: sonarqube
  labels:
    app: postgres
spec:
  ports:
  - port: 5432
  selector:
    app: postgres
EOF

kubectl apply -f /tmp/postgres-with-existing-pvc.yaml

echo ""
echo "=== 5. SURVEILLANCE DU DÉMARRAGE ==="

for i in {1..20}; do
    echo "--- Vérification $i/20 ---"
    kubectl get pods -n $NAMESPACE -l app=postgres
    
    if kubectl get pods -n $NAMESPACE -l app=postgres | grep -q "1/1.*Running"; then
        echo " PostgreSQL est prêt avec le PVC existant!"
        break
    fi
    
    if [ $i -eq 20 ]; then
        echo " Timeout PostgreSQL"
        kubectl describe pods -n $NAMESPACE -l app=postgres
        kubectl logs -l app=postgres -n $NAMESPACE --tail=20
        exit 1
    fi
    
    sleep 15
done

echo ""
echo "=== 6. TEST DE CONNEXION ==="
kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U sonarqube -d sonarqube

echo ""
echo "=== 7. VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE

echo ""
echo " POSTGRESQL OPÉRATIONNEL AVEC PVC EXISTANT!"
echo "=============================================="
echo "PostgreSQL utilise maintenant: postgres-pv-claim-new (10Gi)"
echo "Pas de nouveau quota SSD utilisé!"
echo ""
echo "Vous pouvez maintenant déployer SonarQube avec:"
echo "helm upgrade --install sonarqube sonarqube/sonarqube \\"
echo "  --namespace sonarqube \\"
echo "  --version 2025.3.0 \\"
echo "  --set postgresql.enabled=false \\"
echo "  --set postgresql.postgresqlServer=postgres.sonarqube.svc.cluster.local \\"
echo "  --set postgresql.postgresqlDatabase=sonarqube \\"
echo "  --set postgresql.postgresqlUsername=sonarqube \\"
echo "  --set postgresql.postgresqlPassword=sonarqube \\"
echo "  --set persistence.enabled=true \\"
echo "  --set persistence.size=10Gi \\"
echo "  --set service.type=LoadBalancer \\"
echo "  --set resources.requests.memory=1Gi \\"
echo "  --set resources.requests.cpu=500m \\"
echo "  --set resources.limits.memory=2Gi \\"
echo "  --set resources.limits.cpu=1000m"

# Nettoyage
rm -f /tmp/postgres-with-existing-pvc.yaml

