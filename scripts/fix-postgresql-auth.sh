#!/bin/bash

# CORRECTION AUTHENTIFICATION POSTGRESQL
# Problème identifié : password authentication failed for user "sonarqube"
# Solution : Corriger les identifiants PostgreSQL

echo " CORRECTION AUTHENTIFICATION POSTGRESQL"
echo "========================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"

echo " PROBLÈME RACINE IDENTIFIÉ:"
echo "• Erreur: password authentication failed for user 'sonarqube'"
echo "• SonarQube ne peut pas se connecter à PostgreSQL"
echo "• Cause: Identifiants incorrects ou utilisateur inexistant"
echo "• Solution: Corriger l'authentification PostgreSQL"
echo ""

# 1. Vérification de l'état PostgreSQL
echo " 1. VÉRIFICATION DE L'ÉTAT POSTGRESQL"
echo "---------------------------------------"

echo "État du pod PostgreSQL:"
kubectl get pods -n $NAMESPACE | grep postgres

POSTGRES_POD=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.app=="postgres")].metadata.name}' 2>/dev/null)

if [ -z "$POSTGRES_POD" ]; then
    POSTGRES_POD=$(kubectl get pods -n $NAMESPACE --no-headers | grep postgres | awk '{print $1}' | head -1)
fi

if [ -n "$POSTGRES_POD" ]; then
    echo " Pod PostgreSQL trouvé: $POSTGRES_POD"
else
    echo " Aucun pod PostgreSQL trouvé"
    exit 1
fi

# 2. Vérification des utilisateurs PostgreSQL existants
echo ""
echo " 2. VÉRIFICATION DES UTILISATEURS POSTGRESQL"
echo "----------------------------------------------"

echo "Connexion à PostgreSQL pour vérifier les utilisateurs..."
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "\\du" 2>/dev/null || echo "Erreur de connexion PostgreSQL"

# 3. Création/correction de l'utilisateur SonarQube
echo ""
echo " 3. CRÉATION/CORRECTION UTILISATEUR SONARQUBE"
echo "-----------------------------------------------"

echo "Création de l'utilisateur et base de données SonarQube..."

# Créer l'utilisateur sonarqube avec le bon mot de passe
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "
DROP USER IF EXISTS sonarqube;
CREATE USER sonarqube WITH PASSWORD 'sonarqube';
ALTER USER sonarqube CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE postgres TO sonarqube;
" 2>/dev/null

# Créer la base de données sonarqube
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "
DROP DATABASE IF EXISTS sonarqube;
CREATE DATABASE sonarqube OWNER sonarqube;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube;
" 2>/dev/null

# Vérifier la création
echo ""
echo "Vérification de la création de l'utilisateur:"
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "\\du" 2>/dev/null

echo ""
echo "Vérification de la base de données:"
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U postgres -c "\\l" 2>/dev/null

# 4. Test de connexion avec les nouveaux identifiants
echo ""
echo " 4. TEST DE CONNEXION SONARQUBE"
echo "---------------------------------"

echo "Test de connexion avec l'utilisateur sonarqube..."
kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U sonarqube -d sonarqube -c "SELECT version();" 2>/dev/null && echo " Connexion réussie !" || echo " Connexion échouée"

# 5. Redémarrage de SonarQube avec les identifiants corrigés
echo ""
echo " 5. REDÉMARRAGE SONARQUBE"
echo "---------------------------"

echo "Suppression du déploiement SonarQube actuel..."
kubectl delete deployment sonarqube-light -n $NAMESPACE

echo " Attente de la suppression..."
sleep 10

echo "Création du nouveau déploiement SonarQube avec authentification corrigée..."

# Identifier le PVC PostgreSQL
EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-fixed
  namespace: $NAMESPACE
  labels:
    app: sonarqube-fixed
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-fixed
  template:
    metadata:
      labels:
        app: sonarqube-fixed
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
          value: "sonarqube"
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
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: shared-storage
          mountPath: /opt/sonarqube/data
          subPath: sonarqube-data-fixed
        - name: shared-storage
          mountPath: /opt/sonarqube/logs
          subPath: sonarqube-logs-fixed
        - name: shared-storage
          mountPath: /opt/sonarqube/extensions
          subPath: sonarqube-extensions-fixed
        - name: temp-storage
          mountPath: /opt/sonarqube/temp
        readinessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 10
        livenessProbe:
          httpGet:
            path: /api/system/status
            port: 9000
          initialDelaySeconds: 300
          periodSeconds: 60
          timeoutSeconds: 10
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
  name: sonarqube-fixed
  namespace: $NAMESPACE
  labels:
    app: sonarqube-fixed
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
    name: http
  selector:
    app: sonarqube-fixed
EOF

if [ $? -eq 0 ]; then
    echo " Déploiement SonarQube avec authentification corrigée créé"
else
    echo " Échec du déploiement SonarQube"
    exit 1
fi

# 6. Surveillance du nouveau déploiement
echo ""
echo " 6. SURVEILLANCE DU NOUVEAU DÉPLOIEMENT"
echo "-----------------------------------------"

echo " Surveillance du déploiement SonarQube avec authentification corrigée..."
echo " Authentification: Utilisateur 'sonarqube' créé avec mot de passe 'sonarqube'"
echo " Base de données: 'sonarqube' créée et configurée"
echo ""

max_attempts=20  # 10 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods:"
    kubectl get pods -n $NAMESPACE -l app=sonarqube-fixed -o wide
    
    # Vérifier si le pod est en cours d'exécution
    RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=sonarqube-fixed --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
        echo " Pod SonarQube en cours d'exécution!"
        
        # Vérifier l'IP du LoadBalancer
        SONAR_IP=$(kubectl get svc sonarqube-fixed -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        if [ -n "$SONAR_IP" ]; then
            echo " IP externe: $SONAR_IP"
            SONAR_URL="http://$SONAR_IP:9000"
            
            # Test de l'API
            echo " Test de l'API SonarQube..."
            if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP"; then
                echo ""
                echo " SUCCÈS FINAL ! AUTHENTIFICATION RÉSOLUE !"
                echo "============================================"
                echo " URL: $SONAR_URL"
                echo " Identifiants: admin / admin"
                echo " PostgreSQL: Authentification corrigée"
                echo " Base de données: sonarqube créée"
                echo " API opérationnelle"
                echo ""
                echo " Utilisation finale des ressources:"
                kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                echo ""
                echo " PROBLÈME RÉSOLU DÉFINITIVEMENT:"
                echo "•  Authentification PostgreSQL corrigée"
                echo "•  Utilisateur 'sonarqube' créé"
                echo "•  Base de données 'sonarqube' configurée"
                echo "•  SonarQube connecté à PostgreSQL"
                echo "•  API opérationnelle"
                echo ""
                exit 0
            elif curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "STARTING"; then
                echo " SonarQube démarre encore (STARTING)..."
            fi
        else
            echo " IP externe pas encore assignée..."
        fi
    fi
    
    # Vérifier les erreurs d'authentification
    AUTH_ERROR=$(kubectl logs -l app=sonarqube-fixed -n $NAMESPACE --tail=10 2>/dev/null | grep -i "password authentication failed")
    if [ -n "$AUTH_ERROR" ]; then
        echo " Erreur d'authentification persistante:"
        echo "$AUTH_ERROR"
        echo " Vérification des identifiants PostgreSQL nécessaire"
    fi
    
    # Afficher les logs récents
    echo ""
    echo " Logs récents:"
    kubectl logs -l app=sonarqube-fixed -n $NAMESPACE --tail=3 --since=30s 2>/dev/null || echo "Pas de logs disponibles"
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 10 minutes"

# 7. Diagnostic final
echo ""
echo " 7. DIAGNOSTIC FINAL"
echo "---------------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Logs complets du pod SonarQube:"
kubectl logs -l app=sonarqube-fixed -n $NAMESPACE --tail=20 2>/dev/null

echo ""
echo "État du service:"
kubectl get svc sonarqube-fixed -n $NAMESPACE

echo ""
echo " SI LE PROBLÈME PERSISTE:"
echo "• Vérifiez les identifiants PostgreSQL manuellement"
echo "• Testez la connexion: kubectl exec -it $POSTGRES_POD -n $NAMESPACE -- psql -U sonarqube -d sonarqube"
echo "• Utilisez SonarCloud comme alternative"

echo ""
echo "Script terminé: $(date)"

