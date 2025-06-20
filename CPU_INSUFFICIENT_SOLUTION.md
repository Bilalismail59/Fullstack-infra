#  DIAGNOSTIC : RESSOURCES CPU INSUFFISANTES

##  **PROBLÈME IDENTIFIÉ**

Vos pods PostgreSQL sont en état **Pending** avec l'erreur :
```
0/3 nodes are available: 3 Insufficient cpu. preemption: 0/3 nodes are available: 3 No preemption victims found for incoming pod.
```

##  **ANALYSE DES RESSOURCES**

### État actuel du cluster :
- **Nœud 1** : CPU 896m/940m (95% utilisé)
- **Nœud 2** : CPU 896m/940m (95% utilisé)  
- **Nœud 3** : CPU 818m/940m (87% utilisé)

### Demande PostgreSQL :
- **CPU Request** : 250m
- **CPU Limit** : 500m

** PROBLÈME** : Aucun nœud n'a 250m CPU disponible !

##  **SOLUTIONS IMMÉDIATES**

### **SOLUTION 1 : Réduire les ressources PostgreSQL** ⚡ (RECOMMANDÉE)

```yaml
# Manifeste PostgreSQL avec ressources réduites
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
          value: sonarqube
        - name: POSTGRES_USER
          value: sonarqube
        - name: POSTGRES_PASSWORD
          value: sonarqube123
        resources:
          requests:
            cpu: "100m"      #  Réduit de 250m à 100m
            memory: "128Mi"   #  Réduit de 256Mi à 128Mi
          limits:
            cpu: "200m"      #  Réduit de 500m à 200m
            memory: "256Mi"   # Réduit de 512Mi à 256Mi
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - sonarqube
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pv-claim
```

### **SOLUTION 2 : Nettoyer les ressources inutiles** 

```bash
# 1. Supprimer les anciens pods en erreur
kubectl delete pod sonarqube-854856dbcf-6hrzd -n sonarqube
kubectl delete pod sonarqube-854856dbcf-qd68g -n sonarqube  
kubectl delete pod sonarqube-854856dbcf-xqcm6 -n sonarqube

# 2. Supprimer les anciens deployments PostgreSQL
kubectl delete deployment postgres -n sonarqube

# 3. Nettoyer les ReplicaSets orphelins
kubectl delete rs postgres-5ffc86f6c -n sonarqube
kubectl delete rs postgres-6bd94bdb6f -n sonarqube

# 4. Vérifier les ressources libérées
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### **SOLUTION 3 : Augmenter la taille du cluster** 

```bash
# Augmenter le nombre de nœuds
gcloud container clusters resize primordial-port-462408-q7-gke-cluster \
  --num-nodes=4 \
  --region=europe-west9 \
  --project=primordial-port-462408-q7

# Ou augmenter la taille des nœuds
gcloud container node-pools create larger-pool \
  --cluster=primordial-port-462408-q7-gke-cluster \
  --machine-type=e2-standard-2 \
  --num-nodes=1 \
  --region=europe-west9 \
  --project=primordial-port-462408-q7
```

##  **PLAN D'ACTION RECOMMANDÉ**

### **Étape 1 : Nettoyage immédiat**
```bash
# Supprimer tous les pods en erreur et pending
kubectl delete pods --field-selector=status.phase=Failed -n sonarqube
kubectl delete pods --field-selector=status.phase=Pending -n sonarqube

# Supprimer les deployments problématiques
kubectl delete deployment postgres sonarqube -n sonarqube
```

### **Étape 2 : Redéployer avec ressources réduites**
```bash
# Appliquer le manifeste PostgreSQL optimisé
kubectl apply -f postgres-low-resources.yaml

# Attendre que PostgreSQL démarre
kubectl wait --for=condition=available deployment/postgres -n sonarqube --timeout=300s
```

### **Étape 3 : Redéployer SonarQube avec ressources réduites**
```bash
# SonarQube avec ressources réduites
kubectl apply -f sonarqube-low-resources.yaml
```

##  **MANIFESTES OPTIMISÉS**

### PostgreSQL avec ressources minimales :
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
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        env:
        - name: POSTGRES_DB
          value: sonarqube
        - name: POSTGRES_USER
          value: sonarqube
        - name: POSTGRES_PASSWORD
          value: sonarqube123
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pv-claim
```

### SonarQube avec ressources minimales :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube
  namespace: sonarqube
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
      containers:
      - name: sonarqube
        image: sonarqube:community
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
        env:
        - name: SONAR_JDBC_URL
          value: "jdbc:postgresql://postgres:5432/sonarqube"
        - name: SONAR_JDBC_USERNAME
          value: "sonarqube"
        - name: SONAR_JDBC_PASSWORD
          value: "sonarqube123"
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: sonarqube-data
          mountPath: /opt/sonarqube/data
      volumes:
      - name: sonarqube-data
        persistentVolumeClaim:
          claimName: sonarqube
```

##  **COMMANDES RAPIDES**

```bash
# 1. Nettoyage complet
kubectl delete namespace sonarqube
kubectl create namespace sonarqube

# 2. Redéploiement avec ressources minimales
kubectl apply -f postgres-low-resources.yaml
kubectl apply -f sonarqube-low-resources.yaml

# 3. Surveillance
kubectl get pods -n sonarqube -w
```

##  **RÉSULTAT ATTENDU**

Avec ces ressources réduites :
- **PostgreSQL** : 100m CPU (au lieu de 250m)
- **SonarQube** : 200m CPU (au lieu de plus)

**Total** : 300m CPU disponible sur vos nœuds 

##  **MONITORING POST-DÉPLOIEMENT**

```bash
# Vérifier l'utilisation des ressources
kubectl top nodes
kubectl top pods -n sonarqube

# Vérifier l'état des pods
kubectl get pods -n sonarqube
kubectl describe pods -n sonarqube
```

**Essayez la Solution 1 (ressources réduites) en premier - c'est la plus rapide !** 

