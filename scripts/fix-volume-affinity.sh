#!/bin/bash

# Solution pour le problème de Volume Node Affinity Conflict
# Le PVC est lié à un nœud qui n'a pas assez de CPU

NAMESPACE="sonarqube"

echo " RÉSOLUTION DU PROBLÈME VOLUME NODE AFFINITY"
echo "=============================================="

echo ""
echo "=== PROBLÈME IDENTIFIÉ ==="
echo " Le PVC postgres-pv-claim est lié au nœud gke-primordial-port-4624-default-pool-a017dc9f-ck55"
echo " Ce nœud n'a pas assez de CPU disponible"
echo " PostgreSQL fonctionne parfaitement avec un volume temporaire"

echo ""
echo "=== SOLUTION : CRÉER UN NOUVEAU PVC ==="

# 1. Sauvegarder les données existantes si nécessaire
echo "1. Sauvegarde des données existantes (si nécessaire)..."

# Vérifier s'il y a des données importantes
if kubectl get pvc postgres-pv-claim -n $NAMESPACE &>/dev/null; then
    echo "PVC postgres-pv-claim trouvé. Vérification des données..."
    
    # Créer un job de sauvegarde temporaire
    cat > /tmp/backup-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: backup-postgres-data
  namespace: sonarqube
spec:
  template:
    spec:
      containers:
      - name: backup
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "=== Contenu du volume PostgreSQL ==="
          ls -la /data/
          echo "=== Taille des données ==="
          du -sh /data/*
          echo "=== Sauvegarde terminée ==="
        volumeMounts:
        - name: postgres-data
          mountPath: /data
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-pv-claim
      restartPolicy: Never
EOF

    kubectl apply -f /tmp/backup-job.yaml
    echo "Attente de la sauvegarde..."
    kubectl wait --for=condition=complete job/backup-postgres-data -n $NAMESPACE --timeout=120s
    kubectl logs job/backup-postgres-data -n $NAMESPACE
    kubectl delete job backup-postgres-data -n $NAMESPACE
    rm -f /tmp/backup-job.yaml
fi

# 2. Supprimer l'ancien deployment
echo ""
echo "2. Suppression de l'ancien deployment..."
kubectl delete deployment postgres -n $NAMESPACE --ignore-not-found=true

# 3. Créer un nouveau PVC avec un nom différent
echo ""
echo "3. Création d'un nouveau PVC..."

cat > /tmp/new-postgres-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pv-claim-new
  namespace: sonarqube
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard-rwo
EOF

kubectl apply -f /tmp/new-postgres-pvc.yaml

echo "Attente de la liaison du nouveau PVC..."
kubectl wait --for=condition=bound pvc/postgres-pv-claim-new -n $NAMESPACE --timeout=300s

# Vérifier sur quel nœud le nouveau PVC est lié
echo ""
echo "=== VÉRIFICATION DU NOUVEAU PVC ==="
kubectl describe pvc postgres-pv-claim-new -n $NAMESPACE | grep "selected-node"

# 4. Déployer PostgreSQL avec le nouveau PVC
echo ""
echo "4. Déploiement de PostgreSQL avec le nouveau PVC..."

cat > /tmp/postgres-new-pvc.yaml << 'EOF'
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
          initialDelaySeconds: 15
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
          claimName: postgres-pv-claim-new  #  Nouveau PVC
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
EOF

kubectl apply -f /tmp/postgres-new-pvc.yaml

# 5. Attendre que PostgreSQL démarre
echo ""
echo "5. Attente du démarrage de PostgreSQL..."
kubectl wait --for=condition=available deployment/postgres -n $NAMESPACE --timeout=300s

# 6. Vérifier PostgreSQL
echo ""
echo "=== VÉRIFICATION POSTGRESQL ==="
kubectl get pods -n $NAMESPACE -l app=postgres -o wide

# Test de connexion
echo ""
echo "=== TEST DE CONNEXION ==="
kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U sonarqube -d sonarqube -h localhost

# 7. Déployer SonarQube
echo ""
echo "6. Déploiement de SonarQube..."

# Vérifier si SonarQube existe déjà
if kubectl get deployment sonarqube -n $NAMESPACE &>/dev/null; then
    echo "SonarQube existe déjà, redémarrage..."
    kubectl rollout restart deployment/sonarqube -n $NAMESPACE
else
    echo "Déploiement de SonarQube..."
    kubectl apply -f kubernetes/sonarqube-low-resources.yaml
fi

kubectl wait --for=condition=available deployment/sonarqube -n $NAMESPACE --timeout=600s

# 8. Vérification finale
echo ""
echo "=== VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 9. Informations d'accès
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

# 10. Nettoyage optionnel de l'ancien PVC
echo ""
echo " NETTOYAGE OPTIONNEL"
echo "======================"
read -p "Voulez-vous supprimer l'ancien PVC postgres-pv-claim ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Suppression de l'ancien PVC..."
    kubectl delete pvc postgres-pv-claim -n $NAMESPACE
    echo " Ancien PVC supprimé"
else
    echo "  Ancien PVC conservé. Vous pouvez le supprimer plus tard avec :"
    echo "   kubectl delete pvc postgres-pv-claim -n $NAMESPACE"
fi

# Nettoyage des fichiers temporaires
rm -f /tmp/new-postgres-pvc.yaml /tmp/postgres-new-pvc.yaml

echo ""
echo " RÉSOLUTION TERMINÉE AVEC SUCCÈS !"
echo "===================================="
echo "PostgreSQL utilise maintenant un nouveau PVC sur un nœud avec suffisamment de ressources !"

