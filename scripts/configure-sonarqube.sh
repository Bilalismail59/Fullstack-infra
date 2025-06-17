#!/bin/bash

# Script de configuration SonarQube
# Ce script configure automatiquement les projets SonarQube et génère les tokens

set -e

echo "=== Configuration SonarQube ==="

# Configuration
SONARQUBE_URL="http://localhost:9000"
SONARQUBE_USER="admin"
SONARQUBE_PASSWORD="admin"
NAMESPACE="sonarqube"

# Fonction pour attendre que SonarQube soit prêt
wait_for_sonarqube() {
    echo "Attente de la disponibilité de SonarQube..."
    
    # Port-forward vers SonarQube
    kubectl port-forward -n $NAMESPACE svc/sonarqube-sonarqube 9000:9000 &
    PF_PID=$!
    sleep 15
    
    # Attendre que SonarQube réponde
    for i in {1..30}; do
        if curl -s -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" "$SONARQUBE_URL/api/system/status" | grep -q "UP"; then
            echo "SonarQube est prêt!"
            return 0
        fi
        echo "Attente de SonarQube... ($i/30)"
        sleep 10
    done
    
    echo "Erreur: SonarQube n'est pas disponible"
    kill $PF_PID 2>/dev/null || true
    exit 1
}

# Fonction pour créer un projet SonarQube
create_project() {
    local project_key=$1
    local project_name=$2
    
    echo "Création du projet: $project_name ($project_key)"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/sonar_response.json \
        -X POST \
        -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" \
        -d "name=$project_name&project=$project_key&visibility=public" \
        "$SONARQUBE_URL/api/projects/create")
    
    if [ "$response" = "200" ]; then
        echo "Projet $project_name créé avec succès"
    elif [ "$response" = "400" ]; then
        echo "Projet $project_name existe déjà"
    else
        echo "Erreur lors de la création du projet $project_name (HTTP $response)"
        cat /tmp/sonar_response.json
    fi
}

# Fonction pour générer un token
generate_token() {
    local project_key=$1
    local token_name=$2
    
    echo "Génération du token pour: $project_key"
    
    response=$(curl -s -w "%{http_code}" -o /tmp/token_response.json \
        -X POST \
        -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" \
        -d "name=$token_name&type=PROJECT_ANALYSIS_TOKEN&projectKey=$project_key" \
        "$SONARQUBE_URL/api/user_tokens/generate")
    
    if [ "$response" = "200" ]; then
        token=$(cat /tmp/token_response.json | jq -r '.token')
        echo "Token généré pour $project_key: $token"
        echo "Ajoutez ce token aux secrets GitHub avec le nom: SONAR_TOKEN_$(echo $project_key | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    else
        echo "Erreur lors de la génération du token pour $project_key (HTTP $response)"
        cat /tmp/token_response.json
    fi
}

# Fonction pour configurer les Quality Gates
configure_quality_gates() {
    echo "Configuration des Quality Gates..."
    
    # Créer un Quality Gate personnalisé
    response=$(curl -s -w "%{http_code}" -o /tmp/qg_response.json \
        -X POST \
        -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" \
        -d "name=Fullstack Quality Gate" \
        "$SONARQUBE_URL/api/qualitygates/create")
    
    if [ "$response" = "200" ]; then
        qg_id=$(cat /tmp/qg_response.json | jq -r '.id')
        echo "Quality Gate créé avec l'ID: $qg_id"
        
        # Ajouter des conditions au Quality Gate
        conditions=(
            "new_coverage:LT:80"
            "new_duplicated_lines_density:GT:3"
            "new_maintainability_rating:GT:1"
            "new_reliability_rating:GT:1"
            "new_security_rating:GT:1"
            "new_security_hotspots_reviewed:LT:100"
        )
        
        for condition in "${conditions[@]}"; do
            IFS=':' read -r metric op value <<< "$condition"
            curl -s -X POST \
                -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" \
                -d "gateName=Fullstack Quality Gate&metric=$metric&op=$op&error=$value" \
                "$SONARQUBE_URL/api/qualitygates/create_condition"
        done
        
        echo "Conditions ajoutées au Quality Gate"
    fi
}

# Fonction pour associer les projets au Quality Gate
associate_projects_to_qg() {
    echo "Association des projets au Quality Gate..."
    
    projects=("frontend-app" "backend-app")
    
    for project in "${projects[@]}"; do
        curl -s -X POST \
            -u "$SONARQUBE_USER:$SONARQUBE_PASSWORD" \
            -d "gateName=Fullstack Quality Gate&projectKey=$project" \
            "$SONARQUBE_URL/api/qualitygates/select"
        echo "Projet $project associé au Quality Gate"
    done
}

# Vérification des prérequis
if ! command -v kubectl &> /dev/null; then
    echo "Erreur: kubectl n'est pas installé"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Erreur: curl n'est pas installé"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Erreur: jq n'est pas installé"
    exit 1
fi

# Vérification que SonarQube est déployé
if ! kubectl get deployment sonarqube-sonarqube -n $NAMESPACE &> /dev/null; then
    echo "Erreur: SonarQube n'est pas déployé dans le namespace $NAMESPACE"
    exit 1
fi

# Attendre que SonarQube soit prêt
wait_for_sonarqube

# Créer les projets
create_project "frontend-app" "Frontend Application"
create_project "backend-app" "Backend Application"

# Configurer les Quality Gates
configure_quality_gates

# Associer les projets aux Quality Gates
associate_projects_to_qg

# Générer les tokens
generate_token "frontend-app" "frontend-analysis-token"
generate_token "backend-app" "backend-analysis-token"

# Arrêter le port-forward
kill $PF_PID 2>/dev/null || true

echo "=== Configuration SonarQube terminée ==="
echo ""
echo "Informations importantes:"
echo "- URL SonarQube: $SONARQUBE_URL"
echo "- Utilisateur: $SONARQUBE_USER"
echo "- Mot de passe: $SONARQUBE_PASSWORD"
echo ""
echo "Secrets GitHub à configurer:"
echo "- SONAR_HOST_URL: $SONARQUBE_URL"
echo "- SONAR_TOKEN: (utilisez l'un des tokens générés ci-dessus)"
echo "- SNYK_TOKEN: (token Snyk pour l'analyse de sécurité)"
echo ""
echo "Pour accéder à SonarQube depuis l'extérieur:"
echo "kubectl port-forward -n $NAMESPACE svc/sonarqube-sonarqube 9000:9000"