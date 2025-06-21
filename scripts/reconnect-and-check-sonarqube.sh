#!/bin/bash

# SCRIPT DE RECONNEXION GKE ET VÉRIFICATION SONARQUBE
# Problème : Session Kubernetes expirée (Unauthorized)
# Solution : Reconnexion automatique et vérification de l'état SonarQube

echo " RECONNEXION GKE ET VÉRIFICATION SONARQUBE"
echo "============================================"
echo "Date: $(date)"
echo ""

# Variables du projet
PROJECT_ID="primordial-port-462408-q7"
CLUSTER_NAME="primordial-port-462408-q7-gke-cluster"
CLUSTER_REGION="europe-west9"
NAMESPACE="sonarqube"

echo " PROBLÈME IDENTIFIÉ:"
echo "• Session Kubernetes expirée après ~1h"
echo "• Erreur: 'You must be logged in to the server (Unauthorized)'"
echo "• SonarQube était en cours de déploiement avec 1Gi mémoire"
echo "• Solution: Reconnexion et vérification de l'état"
echo ""

# 1. Reconnexion à GCP et GKE
echo " 1. RECONNEXION À GCP ET GKE"
echo "-----------------------------"

echo "Authentification GCP..."
gcloud auth login --brief || {
    echo " Échec de l'authentification GCP"
    echo " Veuillez suivre les instructions affichées ou exécutez manuellement : gcloud auth login"
    exit 1
}

echo "Configuration du projet..."
gcloud config set project "$PROJECT_ID"

echo "Récupération des credentials GKE..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$CLUSTER_REGION" --project "$PROJECT_ID"

# Test de la connexion
echo ""
echo " Test de la connexion Kubernetes..."
if kubectl get nodes >/dev/null 2>&1; then
    echo " Connexion Kubernetes réussie"
    kubectl get nodes
else
    echo " Échec de la connexion Kubernetes"
    echo ""
    echo " SOLUTION MANUELLE :"
    echo "1. Exécutez : gcloud auth login"
    echo "2. Exécutez : gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION --project $PROJECT_ID"
    echo "3. Relancez ce script"
    exit 1
fi

# 2. Vérification de l'état actuel de SonarQube
echo ""
echo " 2. VÉRIFICATION DE L'ÉTAT SONARQUBE"
echo "-------------------------------------"

echo "État des pods SonarQube:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "État des services SonarQube:"
kubectl get svc -n $NAMESPACE

echo ""
echo "État des PVCs:"
kubectl get pvc -n $NAMESPACE

# 3. Vérifier si SonarQube fonctionne déjà
echo ""
echo " 3. VÉRIFICATION DE L'ACCÈS SONARQUBE"
echo "--------------------------------------"

# Chercher les services SonarQube
SONAR_SERVICES=$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' | tr ' ' '\n' | grep -E '(sonarqube|optimized)')

if [ -n "$SONAR_SERVICES" ]; then
    echo "Services SonarQube trouvés:"
    for service in $SONAR_SERVICES; do
        echo "• $service"
        SONAR_IP=$(kubectl get svc $service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -n "$SONAR_IP" ]; then
            echo "  IP externe: $SONAR_IP"
            SONAR_URL="http://$SONAR_IP:9000"
            
            echo "  Test de l'API..."
            if curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "UP"; then
                echo "   SonarQube OPÉRATIONNEL !"
                echo ""
                echo " SUCCÈS ! SONARQUBE FONCTIONNE !"
                echo "================================="
                echo " URL: $SONAR_URL"
                echo " Identifiants: admin / admin"
                echo " Mémoire: 1Gi (problème OOMKilled résolu)"
                echo " Stockage: Partagé avec PostgreSQL"
                echo ""
                echo " Détails du pod:"
                kubectl get pods -n $NAMESPACE -l app=sonarqube-optimized -o wide 2>/dev/null || kubectl get pods -n $NAMESPACE -o wide
                echo ""
                echo " Utilisation des ressources:"
                kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Métriques non disponibles"
                echo ""
                exit 0
            elif curl -sSf "$SONAR_URL/api/system/status" 2>/dev/null | grep -q "STARTING"; then
                echo "   SonarQube démarre encore..."
            else
                echo "   SonarQube ne répond pas"
            fi
        else
            echo "   IP externe pas encore assignée"
        fi
    done
else
    echo "Aucun service SonarQube LoadBalancer trouvé"
fi

# 4. Vérifier l'état des pods en détail
echo ""
echo " 4. DIAGNOSTIC DÉTAILLÉ DES PODS"
echo "---------------------------------"

SONAR_PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.app)].metadata.name}' | tr ' ' '\n' | grep -E '(sonarqube|optimized)')

if [ -n "$SONAR_PODS" ]; then
    for pod in $SONAR_PODS; do
        echo "=== Pod: $pod ==="
        kubectl get pod $pod -n $NAMESPACE -o wide
        
        echo ""
        echo "Description du pod:"
        kubectl describe pod $pod -n $NAMESPACE | grep -A 10 -E "(Status|Conditions|Events)"
        
        echo ""
        echo "Logs récents (10 dernières lignes):"
        kubectl logs $pod -n $NAMESPACE --tail=10 2>/dev/null || echo "Pas de logs disponibles"
        echo ""
    done
else
    echo "Aucun pod SonarQube trouvé"
fi

# 5. Recommandations basées sur l'état
echo ""
echo " 5. RECOMMANDATIONS"
echo "--------------------"

RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l)
PENDING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "Pending" | wc -l)
CRASHLOOP_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "CrashLoopBackOff" | wc -l)
OOMKILLED_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "OOMKilled" | wc -l)

echo "État actuel:"
echo "• Pods Running: $RUNNING_PODS"
echo "• Pods Pending: $PENDING_PODS"
echo "• Pods CrashLoopBackOff: $CRASHLOOP_PODS"
echo "• Pods OOMKilled: $OOMKILLED_PODS"
echo ""

if [ "$RUNNING_PODS" -gt 0 ]; then
    echo " RECOMMANDATION: SonarQube semble fonctionner"
    echo "• Attendez quelques minutes que l'API soit prête"
    echo "• Testez l'accès via l'IP externe"
elif [ "$OOMKILLED_PODS" -gt 0 ]; then
    echo " RECOMMANDATION: Problème de mémoire persistant"
    echo "• Augmentez encore la mémoire (1.5Gi ou 2Gi)"
    echo "• Ou utilisez une version SonarQube plus légère"
elif [ "$PENDING_PODS" -gt 0 ]; then
    echo " RECOMMANDATION: Problème de scheduling"
    echo "• Vérifiez les ressources disponibles"
    echo "• Vérifiez les quotas et PVCs"
else
    echo " RECOMMANDATION: Relancer le déploiement"
    echo "• Exécutez: ./scripts/fix-oomkilled-memory.sh"
    echo "• Surveillez les logs en temps réel"
fi

echo ""
echo " COMMANDES UTILES:"
echo "• Surveiller les pods: kubectl get pods -n $NAMESPACE -w"
echo "• Voir les logs: kubectl logs -f -l app=sonarqube-optimized -n $NAMESPACE"
echo "• Redémarrer: kubectl rollout restart deployment/sonarqube-memory-optimized -n $NAMESPACE"
echo ""
echo "Script terminé: $(date)"

