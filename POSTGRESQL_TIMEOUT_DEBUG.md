# DÉPANNAGE : PostgreSQL Timeout dans GitHub Actions

## **DIAGNOSTIC DU PROBLÈME**

L'erreur indique que PostgreSQL ne devient pas disponible dans les 5 minutes (300s). Voici les causes possibles et solutions :

## **SOLUTIONS IMMÉDIATES**

### 1. **Augmenter le timeout**
```yaml
# Dans votre workflow GitHub Actions
- name: Wait For PostgreSQL
  run: |
    kubectl wait --for=condition=available --timeout=600s deployment/postgres -n sonarqube
    # Timeout augmenté à 10 minutes
```

### 2. **Vérifier les ressources disponibles**
```yaml
# Ajouter avant le wait
- name: Check Cluster Resources
  run: |
    kubectl get nodes
    kubectl describe nodes
    kubectl get pods -n sonarqube
    kubectl describe pod -l app=postgres -n sonarqube
```

### 3. **Diagnostic détaillé**
```yaml
- name: Debug PostgreSQL Deployment
  run: |
    echo "=== Checking deployment status ==="
    kubectl get deployment postgres -n sonarqube -o yaml
    
    echo "=== Checking pod status ==="
    kubectl get pods -n sonarqube -l app=postgres
    
    echo "=== Checking pod logs ==="
    kubectl logs -l app=postgres -n sonarqube --tail=50
    
    echo "=== Checking events ==="
    kubectl get events -n sonarqube --sort-by='.lastTimestamp'
    
    echo "=== Checking resource usage ==="
    kubectl top nodes
    kubectl top pods -n sonarqube
```

## **CONFIGURATION POSTGRESQL OPTIMISÉE**

### Manifeste PostgreSQL corrigé :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: sonarqube
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
        env:
        - name: POSTGRES_DB
          value: sonar
        - name: POSTGRES_USER
          value: sonar
        - name: POSTGRES_PASSWORD
          value: sonar
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U sonar -d sonar
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U sonar -d sonar
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: sonarqube
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: sonarqube
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard-rwo
```

## **WORKFLOW GITHUB ACTIONS AMÉLIORÉ**

```yaml
name: Deploy SonarQube Infrastructure

on:
  workflow_dispatch:
  push:
    paths:
      - 'kubernetes/sonarqube/**'

env:
  PROJECT_ID: primordial-port-462408-q7
  CLUSTER_NAME: primordial-port-462408-q7-gke-cluster
  CLUSTER_REGION: europe-west9

jobs:
  deploy-sonarqube:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        credentials_json: ${{ secrets.GCP_SA_KEY }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Get GKE credentials
      run: |
        gcloud container clusters get-credentials $CLUSTER_NAME \
          --region $CLUSTER_REGION \
          --project $PROJECT_ID

    - name: Create namespace
      run: |
        kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f -

    - name: Check cluster resources
      run: |
        echo "=== Cluster nodes ==="
        kubectl get nodes -o wide
        
        echo "=== Available resources ==="
        kubectl describe nodes | grep -A 5 "Allocated resources"
        
        echo "=== Storage classes ==="
        kubectl get storageclass

    - name: Deploy PostgreSQL
      run: |
        kubectl apply -f kubernetes/sonarqube/postgres.yaml
        
        echo "=== Deployment created ==="
        kubectl get deployment postgres -n sonarqube

    - name: Wait for PostgreSQL PVC
      run: |
        echo "Waiting for PVC to be bound..."
        kubectl wait --for=condition=bound pvc/postgres-pvc -n sonarqube --timeout=300s

    - name: Monitor PostgreSQL startup
      run: |
        echo "=== Monitoring PostgreSQL startup ==="
        
        # Attendre que le pod soit créé
        timeout 120s bash -c 'until kubectl get pods -n sonarqube -l app=postgres | grep -q postgres; do sleep 5; done'
        
        # Suivre les logs pendant le démarrage
        kubectl logs -f -l app=postgres -n sonarqube --tail=20 &
        LOG_PID=$!
        
        # Attendre que le pod soit prêt
        kubectl wait --for=condition=ready pod -l app=postgres -n sonarqube --timeout=600s
        
        # Arrêter le suivi des logs
        kill $LOG_PID 2>/dev/null || true

    - name: Verify PostgreSQL
      run: |
        echo "=== PostgreSQL verification ==="
        kubectl get pods -n sonarqube -l app=postgres
        kubectl get svc postgres -n sonarqube
        
        # Test de connexion
        kubectl exec -n sonarqube deployment/postgres -- pg_isready -U sonar -d sonar

    - name: Deploy SonarQube
      run: |
        kubectl apply -f kubernetes/sonarqube/sonarqube.yaml

    - name: Wait for SonarQube
      run: |
        echo "Waiting for SonarQube to be ready..."
        kubectl wait --for=condition=available deployment/sonarqube -n sonarqube --timeout=900s

    - name: Get SonarQube URL
      run: |
        echo "=== SonarQube deployment completed ==="
        kubectl get pods -n sonarqube
        kubectl get svc -n sonarqube
        
        # Si vous avez un ingress ou LoadBalancer
        kubectl get ingress -n sonarqube || echo "No ingress found"

    - name: Cleanup on failure
      if: failure()
      run: |
        echo "=== Debugging information ==="
        kubectl get all -n sonarqube
        kubectl describe pods -n sonarqube
        kubectl get events -n sonarqube --sort-by='.lastTimestamp'
        
        echo "=== PostgreSQL logs ==="
        kubectl logs -l app=postgres -n sonarqube --tail=100 || true
        
        echo "=== SonarQube logs ==="
        kubectl logs -l app=sonarqube -n sonarqube --tail=100 || true
```

## **CAUSES COMMUNES ET SOLUTIONS**

### 1. **Ressources insuffisantes**
```bash
# Vérifier les ressources du cluster
kubectl describe nodes
kubectl top nodes
```

**Solution :** Réduire les ressources demandées ou augmenter la taille du cluster.

### 2. **Problème de stockage**
```bash
# Vérifier les PVC
kubectl get pvc -n sonarqube
kubectl describe pvc postgres-pvc -n sonarqube
```

**Solution :** Vérifier que la StorageClass existe et fonctionne.

### 3. **Image PostgreSQL qui ne démarre pas**
```bash
# Vérifier les logs
kubectl logs -l app=postgres -n sonarqube
```

**Solutions possibles :**
- Problème de permissions sur le volume
- Configuration PostgreSQL incorrecte
- Ressources insuffisantes

### 4. **Problème réseau**
```bash
# Vérifier la connectivité
kubectl get networkpolicies -n sonarqube
```

## **SOLUTION RAPIDE POUR VOTRE CAS**

Modifiez votre workflow pour ajouter plus de diagnostic :

```yaml
- name: Enhanced PostgreSQL Wait
  run: |
    echo "Starting PostgreSQL deployment monitoring..."
    
    # Attendre que le deployment soit créé
    kubectl wait --for=condition=progressing deployment/postgres -n sonarqube --timeout=60s
    
    # Surveiller le démarrage
    for i in {1..30}; do
      echo "=== Check $i/30 ==="
      kubectl get pods -n sonarqube -l app=postgres
      
      # Vérifier si le pod est prêt
      if kubectl get pods -n sonarqube -l app=postgres | grep -q "1/1.*Running"; then
        echo "PostgreSQL is ready!"
        break
      fi
      
      # Afficher les logs si le pod existe
      if kubectl get pods -n sonarqube -l app=postgres | grep -q postgres; then
        echo "=== PostgreSQL logs ==="
        kubectl logs -l app=postgres -n sonarqube --tail=10
      fi
      
      sleep 20
    done
    
    # Vérification finale
    kubectl wait --for=condition=available deployment/postgres -n sonarqube --timeout=60s
```

## **RECOMMANDATIONS**

1. **Augmentez le timeout** à 10-15 minutes
2. **Ajoutez plus de monitoring** pendant le déploiement
3. **Vérifiez les ressources** du cluster avant le déploiement
4. **Utilisez des readiness probes** appropriées
5. **Surveillez les logs** en temps réel

Essayez ces solutions et dites-moi quels sont les résultats ! 🚀

