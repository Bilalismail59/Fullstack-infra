#  CORRECTION RAPIDE DU PROBLÈME PVC

##  **BONNE NOUVELLE !**

Le nettoyage a **FONCTIONNÉ** ! Regardez les ressources CPU :
- **Avant** : Nœud 3 à 87% CPU
- **Après** : Nœud 3 à **47% CPU** 

**Vous avez maintenant assez de ressources pour PostgreSQL !**

##  **PROBLÈME RESTANT**

L'erreur PVC : `field can not be less than status.capacity`

**Cause** : Le PVC `postgres-pv-claim` existe déjà avec **10Gi**, on ne peut pas le réduire à **5Gi**.

##  **SOLUTION IMMÉDIATE**

### **Exécutez simplement :**
```bash
# Télécharger et exécuter le script de correction
./scripts/fix-pvc-issue.sh
```

### **Ou manuellement :**
```bash
# 1. Supprimer le deployment PostgreSQL en erreur
kubectl delete deployment postgres -n sonarqube

# 2. Créer PostgreSQL avec le PVC existant (10Gi)
kubectl apply -f - << 'EOF'
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
            cpu: "100m"      #  Ressources réduites
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "sonarqube", "-d", "sonarqube"]
          initialDelaySeconds: 15
          periodSeconds: 5
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "sonarqube", "-d", "sonarqube"]
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pv-claim  #  Utilise le PVC existant 10Gi
      securityContext:
        fsGroup: 999
        runAsUser: 999
EOF

# 3. Attendre PostgreSQL
kubectl wait --for=condition=available deployment/postgres -n sonarqube --timeout=300s

# 4. Déployer SonarQube
kubectl apply -f kubernetes/sonarqube-low-resources.yaml
kubectl wait --for=condition=available deployment/sonarqube -n sonarqube --timeout=600s
```

##  **POURQUOI ÇA VA MARCHER MAINTENANT**

1. ** CPU libéré** : 47% au lieu de 87% sur le nœud 3
2. ** Pods nettoyés** : Plus de pods en erreur qui consomment des ressources
3. ** Ressources optimisées** : PostgreSQL ne demande que 100m CPU
4. ** PVC existant** : On garde le volume 10Gi existant

##  **RESSOURCES APRÈS CORRECTION**

- **PostgreSQL** : 100m CPU + 128Mi RAM 
- **SonarQube** : 200m CPU + 512Mi RAM 
- **Total** : 300m CPU (largement disponible maintenant)

##  **RÉSULTAT ATTENDU**

Après la correction :
1. PostgreSQL démarre en **2-3 minutes**
2. SonarQube démarre en **5-8 minutes**
3. Accès via LoadBalancer ou port-forward

**Lancez le script de correction et tout devrait fonctionner !** 🎉

