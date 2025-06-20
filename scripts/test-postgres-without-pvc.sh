#!/bin/bash

# Solution alternative : PostgreSQL sans volume persistant pour test
# Si le problème vient du PVC, on teste avec un volume temporaire

NAMESPACE="sonarqube"

echo " TEST POSTGRESQL SANS VOLUME PERSISTANT"
echo "========================================="

echo ""
echo "=== NETTOYAGE COMPLET ==="
kubectl delete deployment postgres -n $NAMESPACE --ignore-not-found=true
kubectl delete pod --all -n $NAMESPACE --ignore-not-found=true

echo "Attente du nettoyage..."
sleep 10

echo ""
echo "=== DÉPLOIEMENT POSTGRESQL DE TEST ==="
echo "PostgreSQL avec volume temporaire (emptyDir) pour diagnostic..."

cat > /tmp/postgres-test.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-test
  namespace: sonarqube
  labels:
    app: postgres-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-test
  template:
    metadata:
      labels:
        app: postgres-test
    spec:
      containers:
      - name: postgres
        image: postgres:13
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: sonarqube
        - name: POSTGRES_USER
          value: sonarqube
        - name: POSTGRES_PASSWORD
          value: sonarqube123
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            cpu: "100m"
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
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 6
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
      volumes:
      - name: postgres-storage
        emptyDir: {}  # Volume temporaire pour test
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-test
  namespace: sonarqube
spec:
  selector:
    app: postgres-test
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

kubectl apply -f /tmp/postgres-test.yaml

echo ""
echo "=== SURVEILLANCE DU DÉMARRAGE ==="
echo "Surveillance en temps réel (30 secondes)..."

for i in {1..6}; do
    echo "--- Vérification $i/6 ---"
    kubectl get pods -n $NAMESPACE -l app=postgres-test
    
    # Vérifier si le pod est prêt
    if kubectl get pods -n $NAMESPACE -l app=postgres-test | grep -q "1/1.*Running"; then
        echo " PostgreSQL de test est prêt!"
        break
    fi
    
    # Afficher les logs si disponibles
    POSTGRES_POD=$(kubectl get pods -n $NAMESPACE -l app=postgres-test -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POSTGRES_POD" ]; then
        echo "Logs actuels:"
        kubectl logs $POSTGRES_POD -n $NAMESPACE --tail=5 2>/dev/null || echo "Pas de logs encore"
    fi
    
    sleep 5
done

echo ""
echo "=== RÉSULTAT DU TEST ==="
kubectl get pods -n $NAMESPACE -l app=postgres-test

POSTGRES_POD=$(kubectl get pods -n $NAMESPACE -l app=postgres-test -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if kubectl get pods -n $NAMESPACE -l app=postgres-test | grep -q "1/1.*Running"; then
    echo " SUCCÈS: PostgreSQL fonctionne avec un volume temporaire"
    echo " PROBLÈME: Le PVC postgres-pv-claim a un problème"
    echo ""
    echo " SOLUTIONS:"
    echo "1. Supprimer et recréer le PVC"
    echo "2. Vérifier les permissions du volume"
    echo "3. Utiliser un nouveau PVC avec un nom différent"
    
    # Test de connexion
    echo ""
    echo "=== TEST DE CONNEXION ==="
    kubectl exec -n $NAMESPACE $POSTGRES_POD -- pg_isready -U sonarqube -d sonarqube -h localhost
    
else
    echo " ÉCHEC: PostgreSQL ne fonctionne pas même avec un volume temporaire"
    echo " PROBLÈME: Configuration PostgreSQL ou ressources"
    echo ""
    echo " SOLUTIONS:"
    echo "1. Vérifier les logs détaillés"
    echo "2. Vérifier les ressources du cluster"
    echo "3. Essayer une image PostgreSQL différente"
    
    if [ -n "$POSTGRES_POD" ]; then
        echo ""
        echo "=== LOGS DÉTAILLÉS ==="
        kubectl logs $POSTGRES_POD -n $NAMESPACE
        
        echo ""
        echo "=== DESCRIPTION DU POD ==="
        kubectl describe pod $POSTGRES_POD -n $NAMESPACE
    fi
fi

echo ""
echo "=== NETTOYAGE DU TEST ==="
kubectl delete -f /tmp/postgres-test.yaml
rm -f /tmp/postgres-test.yaml

echo ""
echo " PROCHAINES ÉTAPES RECOMMANDÉES"
echo "================================="

if kubectl get pods -n $NAMESPACE -l app=postgres-test | grep -q "1/1.*Running"; then
    echo "Le problème vient du PVC. Solutions:"
    echo "1. ./scripts/recreate-pvc.sh (script à créer)"
    echo "2. Utiliser un nouveau nom de PVC"
    echo "3. Vérifier les permissions du volume GCP"
else
    echo "Le problème est plus profond. Solutions:"
    echo "1. Vérifier les ressources du cluster"
    echo "2. Essayer une configuration PostgreSQL plus simple"
    echo "3. Vérifier les politiques de sécurité du cluster"
fi

