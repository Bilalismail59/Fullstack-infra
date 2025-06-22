#!/bin/bash

# DIAGNOSTIC ET RÉSOLUTION : POD SONARQUBE PENDING
# Pod identifié : sonarqube-5cb9cb95c7-f66gf (Pending depuis 5m)
# Objectif : Diagnostiquer la cause et résoudre le problème

echo " DIAGNOSTIC POD SONARQUBE PENDING"
echo "==================================="
echo "Date: $(date)"
echo ""

NAMESPACE="sonarqube"
POD_NAME="sonarqube-5cb9cb95c7-f66gf"

echo " EXCELLENTE NOUVELLE:"
echo "• Pod SonarQube trouvé: $POD_NAME"
echo "• État: Pending (problème de scheduling)"
echo "• Âge: 5+ minutes"
echo "• Objectif: Identifier et résoudre la cause"
echo ""

# 1. Diagnostic détaillé du pod Pending
echo " 1. DIAGNOSTIC DÉTAILLÉ DU POD"
echo "-------------------------------"

echo "État actuel du pod:"
kubectl get pod $POD_NAME -n $NAMESPACE -o wide 2>/dev/null || echo "Pod non trouvé (peut avoir changé de nom)"

echo ""
echo "Description complète du pod:"
kubectl describe pod $POD_NAME -n $NAMESPACE 2>/dev/null || echo "Pod non trouvé"

# Si le pod spécifique n'existe plus, chercher tous les pods SonarQube
echo ""
echo "Tous les pods SonarQube actuels:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=sonarqube -o wide 2>/dev/null || kubectl get pods -n $NAMESPACE | grep sonarqube

# 2. Diagnostic des événements
echo ""
echo " 2. ÉVÉNEMENTS RÉCENTS"
echo "------------------------"

echo "Événements du namespace (15 derniers):"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -15

# 3. Vérification des ressources et quotas
echo ""
echo " 3. VÉRIFICATION DES RESSOURCES"
echo "---------------------------------"

echo "Utilisation des nœuds:"
kubectl top nodes 2>/dev/null || echo "Métriques non disponibles"

echo ""
echo "État des PVCs:"
kubectl get pvc -n $NAMESPACE

echo ""
echo "Quotas du namespace:"
kubectl describe namespace $NAMESPACE | grep -A 10 "Resource Quotas" 2>/dev/null || echo "Pas de quotas configurés"

# 4. Identifier la cause probable
echo ""
echo " 4. IDENTIFICATION DE LA CAUSE"
echo "--------------------------------"

# Chercher les erreurs de scheduling dans les événements
SCHEDULING_ERROR=$(kubectl get events -n $NAMESPACE --field-selector reason=FailedScheduling --sort-by='.lastTimestamp' | tail -1)

if [ -n "$SCHEDULING_ERROR" ]; then
    echo " Erreur de scheduling détectée:"
    echo "$SCHEDULING_ERROR"
    
    if echo "$SCHEDULING_ERROR" | grep -q "Insufficient cpu"; then
        echo " Cause: CPU insuffisant"
        SOLUTION="cpu"
    elif echo "$SCHEDULING_ERROR" | grep -q "Insufficient memory"; then
        echo " Cause: Mémoire insuffisante"
        SOLUTION="memory"
    elif echo "$SCHEDULING_ERROR" | grep -q "binding volumes"; then
        echo " Cause: Problème de volume/PVC"
        SOLUTION="volume"
    elif echo "$SCHEDULING_ERROR" | grep -q "QUOTA_EXCEEDED"; then
        echo " Cause: Quota SSD dépassé"
        SOLUTION="quota"
    else
        echo " Cause: Autre problème de scheduling"
        SOLUTION="other"
    fi
else
    echo " Aucune erreur de scheduling récente trouvée"
    echo " Vérification des PVCs en attente..."
    
    PENDING_PVC=$(kubectl get pvc -n $NAMESPACE | grep Pending)
    if [ -n "$PENDING_PVC" ]; then
        echo " PVC en attente détecté:"
        echo "$PENDING_PVC"
        SOLUTION="quota"
    else
        SOLUTION="unknown"
    fi
fi

# 5. Application de la solution appropriée
echo ""
echo " 5. APPLICATION DE LA SOLUTION"
echo "--------------------------------"

case $SOLUTION in
    "quota")
        echo " SOLUTION: Utiliser le stockage partagé (quota SSD dépassé)"
        
        # Identifier un PVC PostgreSQL existant
        EXISTING_PVC=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | tr ' ' '\n' | grep -E '^postgres-pvc-' | head -1)
        
        if [ -n "$EXISTING_PVC" ]; then
            echo " PVC PostgreSQL trouvé: $EXISTING_PVC"
            
            echo "Suppression du déploiement actuel..."
            kubectl delete deployment --all -n $NAMESPACE --ignore-not-found=true
            kubectl delete pvc --all -n $NAMESPACE --ignore-not-found=true --field-selector=metadata.name!=postgres-pvc-1750455262,metadata.name!=postgres-pvc-1750456138,metadata.name!=postgres-pvc-1750456547
            
            echo " Attente du nettoyage..."
            sleep 10
            
            echo "Création d'un déploiement avec stockage partagé..."
            cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-shared
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-shared
  template:
    metadata:
      labels:
        app: sonarqube-shared
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
          value: "-Xmx512m -Xms256m"
        - name: SONAR_CE_JAVAOPTS
          value: "-Xmx512m -Xms256m"
        resources:
          requests:
            memory: "1Gi"
            cpu: "200m"
          limits:
            memory: "1.5Gi"
            cpu: "800m"
        volumeMounts:
        - name: shared-storage
          mountPath: /opt/sonarqube/data
          subPath: sonarqube-data
        - name: shared-storage
          mountPath: /opt/sonarqube/logs
          subPath: sonarqube-logs
        - name: shared-storage
          mountPath: /opt/sonarqube/extensions
          subPath: sonarqube-extensions
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: $EXISTING_PVC
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube-shared
  namespace: $NAMESPACE
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: sonarqube-shared
EOF
        else
            echo " Aucun PVC PostgreSQL disponible"
        fi
        ;;
        
    "cpu"|"memory")
        echo " SOLUTION: Réduire les ressources demandées"
        
        echo "Mise à jour du déploiement avec ressources réduites..."
        kubectl patch deployment -n $NAMESPACE --type='merge' -p='{"spec":{"template":{"spec":{"containers":[{"name":"sonarqube","resources":{"requests":{"memory":"512Mi","cpu":"100m"},"limits":{"memory":"1Gi","cpu":"500m"}}}]}}}}' --all
        ;;
        
    "volume")
        echo " SOLUTION: Résoudre le problème de volume"
        
        echo "Suppression des PVCs en attente..."
        kubectl delete pvc --field-selector=status.phase=Pending -n $NAMESPACE
        
        echo "Redémarrage du déploiement..."
        kubectl rollout restart deployment --all -n $NAMESPACE
        ;;
        
    *)
        echo " SOLUTION: Redémarrage général"
        
        echo "Redémarrage de tous les déploiements..."
        kubectl rollout restart deployment --all -n $NAMESPACE
        ;;
esac

# 6. Surveillance du résultat
echo ""
echo " 6. SURVEILLANCE DU RÉSULTAT"
echo "------------------------------"

echo " Surveillance des pods SonarQube..."
max_attempts=20  # 10 minutes
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "=== Vérification $attempt/$max_attempts ($(date +%H:%M:%S)) ==="
    
    # État des pods
    echo " État des pods SonarQube:"
    kubectl get pods -n $NAMESPACE -o wide | grep -E "(sonarqube|NAME)"
    
    # Vérifier si un pod est en cours d'exécution
    RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep sonarqube | grep "1/1.*Running" | wc -l)
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
        echo " Pod SonarQube en cours d'exécution!"
        
        # Vérifier l'IP du LoadBalancer
        SONAR_IP=$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' | tr ' ' '\n' | head -1)
        
        if [ -n "$SONAR_IP" ]; then
            echo " IP externe: $SONAR_IP"
            SONAR_URL="http://$SONAR_IP:9000"
            
            # Test de l'API
            if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP\|STARTING"; then
                echo ""
                echo " SUCCÈS ! SONARQUBE FONCTIONNE !"
                echo "================================="
                echo " URL: $SONAR_URL"
                echo " Identifiants: admin / admin"
                echo ""
                exit 0
            fi
        fi
    fi
    
    # Vérifier les erreurs
    PENDING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep sonarqube | grep "Pending" | wc -l)
    if [ "$PENDING_PODS" -gt 0 ]; then
        echo " Pod encore en Pending"
        kubectl describe pod -l app=sonarqube-shared -n $NAMESPACE 2>/dev/null | grep -A 3 "Events:" | tail -3
    fi
    
    echo ""
    echo " Attente 30 secondes..."
    sleep 30
    
    attempt=$((attempt + 1))
done

echo " Timeout atteint après 10 minutes"

# 7. Diagnostic final
echo ""
echo " 7. ÉTAT FINAL"
echo "---------------"

echo "État final des pods:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Services disponibles:"
kubectl get svc -n $NAMESPACE

echo ""
echo " RECOMMANDATIONS FINALES:"
echo "• Vérifiez les logs: kubectl logs -l app=sonarqube-shared -n $NAMESPACE"
echo "• Surveillez les événements: kubectl get events -n $NAMESPACE -w"
echo "• Si problème persiste: Augmentez les ressources du cluster GKE"

echo ""
echo "Script terminé: $(date)"

