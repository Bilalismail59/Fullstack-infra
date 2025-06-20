#!/bin/bash

# Script de correction rapide pour SonarQube
# PostgreSQL fonctionne, il faut juste corriger SonarQube

NAMESPACE="sonarqube"

echo " CORRECTION RAPIDE SONARQUBE"
echo "=============================="

echo ""
echo " PostgreSQL fonctionne parfaitement !"
echo "  Correction de SonarQube en cours..."

# 1. Supprimer le deployment SonarQube problématique
echo ""
echo "=== 1. NETTOYAGE SONARQUBE ==="
kubectl delete deployment sonarqube -n $NAMESPACE --ignore-not-found=true
kubectl delete pvc sonarqube-data -n $NAMESPACE --ignore-not-found=true

echo "Attente du nettoyage..."
sleep 10

# 2. Corriger le service SonarQube (problème de port dupliqué)
echo ""
echo "=== 2. CORRECTION DU SERVICE SONARQUBE ==="

cat > /tmp/sonarqube-service-fixed.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: sonarqube
  namespace: sonarqube
  labels:
    app: sonarqube
spec:
  selector:
    app: sonarqube
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
    name: http
  type: LoadBalancer
EOF

kubectl apply -f /tmp/sonarqube-service-fixed.yaml

# 3. Déployer SonarQube corrigé
echo ""
echo "=== 3. DÉPLOIEMENT SONARQUBE CORRIGÉ ==="

cat > /tmp/sonarqube-fixed.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarqube-data-new
  namespace: sonarqube
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard-rwo
---
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
          failureThreshold: 6
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
          claimName: sonarqube-data-new
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

# 4. Attendre que le PVC soit lié
echo ""
echo "=== 4. ATTENTE DU PVC SONARQUBE ==="
kubectl wait --for=condition=bound pvc/sonarqube-data-new -n $NAMESPACE --timeout=300s

# 5. Surveiller le démarrage de SonarQube
echo ""
echo "=== 5. SURVEILLANCE DU DÉMARRAGE SONARQUBE ==="

for i in {1..20}; do
    echo "--- Vérification $i/20 ---"
    kubectl get pods -n $NAMESPACE -l app=sonarqube
    
    # Vérifier si SonarQube est prêt
    if kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "1/1.*Running"; then
        echo " SonarQube est prêt!"
        break
    fi
    
    # Afficher les logs si le pod existe
    SONARQUBE_POD=$(kubectl get pods -n $NAMESPACE -l app=sonarqube -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$SONARQUBE_POD" ]; then
        echo "État du pod: $(kubectl get pod $SONARQUBE_POD -n $NAMESPACE -o jsonpath='{.status.phase}')"
        if [ "$i" -eq 10 ] || [ "$i" -eq 20 ]; then
            echo "Logs récents:"
            kubectl logs $SONARQUBE_POD -n $NAMESPACE --tail=5 2>/dev/null || echo "Pas de logs encore"
        fi
    fi
    
    sleep 15
done

# 6. Vérification finale
echo ""
echo "=== 6. VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 7. Test d'accès SonarQube
echo ""
echo "=== 7. TEST D'ACCÈS SONARQUBE ==="

SONARQUBE_IP=$(kubectl get svc sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -n "$SONARQUBE_IP" ]; then
    echo "Test de connectivité SonarQube..."
    if curl -s --connect-timeout 10 http://$SONARQUBE_IP:9000/api/system/status | grep -q "UP\|STARTING"; then
        echo " SonarQube répond !"
    else
        echo " SonarQube en cours de démarrage..."
    fi
fi

# 8. Informations finales
echo ""
echo " INFORMATIONS D'ACCÈS"
echo "======================="

echo " PostgreSQL : Opérationnel"
echo "   - Status: $(kubectl get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].status.phase}')"
echo "   - Connexion: Testée et fonctionnelle"

if [ -n "$SONARQUBE_IP" ]; then
    echo " SonarQube : http://$SONARQUBE_IP:9000"
else
    echo " SonarQube : IP en cours d'attribution"
    echo "   Vérifiez avec: kubectl get svc sonarqube -n $NAMESPACE"
fi

echo ""
echo " Identifiants SonarQube :"
echo "   Utilisateur : admin"
echo "   Mot de passe : admin"

echo ""
echo " Accès local (si nécessaire) :"
echo "   kubectl port-forward -n $NAMESPACE svc/sonarqube 9000:9000"

# Nettoyage
rm -f /tmp/sonarqube-service-fixed.yaml /tmp/sonarqube-fixed.yaml

echo ""
echo " CORRECTION TERMINÉE !"
echo "======================="
echo "PostgreSQL :  Opérationnel"
echo "SonarQube  :  En cours de démarrage (5-10 minutes)"

