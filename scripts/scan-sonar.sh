#!/bin/bash

# Se placer à la racine du projet (ex: Fullstack-infra)
cd "$(dirname "$0")/.."

# Variables de configuration
export SONAR_PROJECT_KEY="Bilalismail59_Fullstack-infra"
export SONAR_ORGANIZATION="bilalismail59"
export SONAR_HOST_URL="https://sonarcloud.io"
export SONAR_TOKEN="8dff682e499330d97cb20aaa7ed12f24eb06305e"

# Nettoyage d'anciens fichiers de couverture (optionnel mais recommandé)
rm -f backend-app/.coverage backend-app/coverage.xml

# Génération du rapport de couverture
cd backend-app
coverage run -m pytest
coverage xml -o coverage.xml
cd ..

# Lancer l'analyse SonarCloud avec les bons chemins
~/sonar-scanner/bin/sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.organization="$SONAR_ORGANIZATION" \
  -Dsonar.sources=backend-app/src \
  -Dsonar.tests=backend-app/tests \
  -Dsonar.python.coverage.reportPaths=backend-app/coverage.xml \
  -Dsonar.exclusions="**/venv/**,**/__pycache__/**" \
  -Dsonar.inclusions="backend-app/src/**" \
  -Dsonar.sourceEncoding=UTF-8 \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.login="$SONAR_TOKEN"