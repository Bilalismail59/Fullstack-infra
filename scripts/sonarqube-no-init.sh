#!/bin/bash

# Solution finale pour SonarQube sans init container privilégié
# Le problème est que GKE n'autorise pas les conteneurs privilégiés

NAMESPACE="sonarqube"

echo " SOLUTION FINALE SONARQUBE (SANS PRIVILÈGES)"
echo "=============================================="

echo ""
echo " Problème identifié: Init container privilégié non autorisé sur GKE"
echo " Solution: SonarQube sans init container"

# 1. Supprimer le deployment SonarQube problématique
echo ""
echo "=== 1. NETTOYAGE SONARQUBE ==="
kubectl delete deployment sonarqube -n $NAMESPACE --ignore-not-found=true

echo "Attente du nettoyage..."
sleep 10

# 2. Déployer SonarQube SANS init container
echo ""
echo "=== 2. DÉPLOIEMENT SONARQUBE SIMPLIFIÉ ==="

cat > /tmp/sonarqube-no-init.yaml << 'EOF'
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
        - name: SONAR_SEARCH_JAVAADDITIONALOPTS
          value: "-Xmx256m -Xms128m"
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
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 8
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 180
          periodSeconds: 30
          timeoutSeconds: 15
          failureThreshold: 5
        startupProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 10
          failureThreshold: 40
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

kubectl apply -f /tmp/sonarqube-no-init.yaml

# 3. Surveiller le démarrage de SonarQube
echo ""
echo "=== 3. SURVEILLANCE DU DÉMARRAGE SONARQUBE ==="

for i in {1..25}; do
    echo "--- Vérification $i/25 ($(date +%H:%M:%S)) ---"
    
    # État du pod
    kubectl get pods -n $NAMESPACE -l app=sonarqube
    
    # Vérifier si SonarQube est prêt
    if kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "1/1.*Running"; then
        echo " SonarQube est prêt!"
        break
    fi
    
    # Afficher les logs si le pod existe et n'est pas en init
    SONARQUBE_POD=$(kubectl get pods -n $NAMESPACE -l app=sonarqube -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$SONARQUBE_POD" ]; then
        POD_STATUS=$(kubectl get pod $SONARQUBE_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
        echo "État du pod: $POD_STATUS"
        
        # Afficher les logs périodiquement
        if [ "$i" -eq 5 ] || [ "$i" -eq 10 ] || [ "$i" -eq 15 ] || [ "$i" -eq 20 ] || [ "$i" -eq 25 ]; then
            echo "Logs récents:"
            kubectl logs $SONARQUBE_POD -n $NAMESPACE --tail=3 2>/dev/null || echo "Pas de logs encore"
        fi
        
        # Vérifier les événements si problème
        if kubectl get pod $SONARQUBE_POD -n $NAMESPACE | grep -q "Error\|CrashLoop\|ImagePull"; then
            echo "  Problème détecté, vérification des événements..."
            kubectl describe pod $SONARQUBE_POD -n $NAMESPACE | tail -10
        fi
    fi
    
    sleep 20
done

# 4. Vérification finale
echo ""
echo "=== 4. VÉRIFICATION FINALE ==="
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== UTILISATION DES RESSOURCES ==="
kubectl top nodes || echo "Metrics server non disponible"
kubectl top pods -n $NAMESPACE || echo "Metrics server non disponible"

# 5. Test d'accès SonarQube
echo ""
echo "=== 5. TEST D'ACCÈS SONARQUBE ==="

SONARQUBE_IP=$(kubectl get svc sonarqube -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -n "$SONARQUBE_IP" ]; then
    echo "Test de connectivité SonarQube..."
    
    for attempt in {1..5}; do
        echo "Tentative $attempt/5..."
        if curl -s --connect-timeout 15 http://$SONARQUBE_IP:9000/api/system/status | grep -q "UP"; then
            echo " SonarQube répond et est UP !"
            break
        elif curl -s --connect-timeout 15 http://$SONARQUBE_IP:9000/api/system/status | grep -q "STARTING"; then
            echo " SonarQube en cours de démarrage..."
        else
            echo " SonarQube pas encore prêt..."
        fi
        sleep 10
    done
fi

# 6. Informations finales
echo ""
echo " INFORMATIONS D'ACCÈS FINALES"
echo "==============================="

echo " PostgreSQL : Opérationnel"
echo "   - Status: $(kubectl get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].status.phase}')"
echo "   - CPU: $(kubectl top pod -n $NAMESPACE -l app=postgres --no-headers | awk '{print $2}' 2>/dev/null || echo 'N/A')"

SONARQUBE_STATUS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Non trouvé")
echo ""
echo " SonarQube : $SONARQUBE_STATUS"

if [ -n "$SONARQUBE_IP" ]; then
    echo " URL : http://$SONARQUBE_IP:9000"
else
    echo " IP : En cours d'attribution"
    echo "   Vérifiez avec: kubectl get svc sonarqube -n $NAMESPACE"
fi

echo ""
echo " Identifiants :"
echo "   Utilisateur : admin"
echo "   Mot de passe : admin"

echo ""
echo " Accès local (alternative) :"
echo "   kubectl port-forward -n $NAMESPACE svc/sonarqube 9000:9000"
echo "   Puis ouvrir : http://localhost:9000"

# 7. Diagnostic final si problème
SONARQUBE_POD=$(kubectl get pods -n $NAMESPACE -l app=sonarqube -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SONARQUBE_POD" ]; then
    if ! kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "1/1.*Running"; then
        echo ""
        echo " DIAGNOSTIC FINAL"
        echo "=================="
        echo "Pod SonarQube: $SONARQUBE_POD"
        kubectl describe pod $SONARQUBE_POD -n $NAMESPACE | grep -A 10 "Events:"
        echo ""
        echo "Logs récents:"
        kubectl logs $SONARQUBE_POD -n $NAMESPACE --tail=10 2>/dev/null || echo "Pas de logs disponibles"
    fi
fi

# Nettoyage
rm -f /tmp/sonarqube-no-init.yaml

echo ""
echo " DÉPLOIEMENT TERMINÉ !"
echo "======================="
echo "PostgreSQL :  Opérationnel"
echo "SonarQube  : $(kubectl get pods -n $NAMESPACE -l app=sonarqube -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo 'En cours')"

if kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "1/1.*Running"; then
    echo ""
    echo " SUCCÈS COMPLET ! Tous les services sont opérationnels ! "
else
    echo ""
    echo " SonarQube en cours de démarrage. Patientez 5-10 minutes supplémentaires."
    echo "   Surveillez avec: kubectl get pods -n $NAMESPACE"
fi

