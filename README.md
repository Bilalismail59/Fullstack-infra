# Projet de Déploiement Full Stack sur Google Cloud

Ce projet vise à déployer une application full stack avec une architecture trois tiers sur Google Cloud Platform (GCP). L'objectif est de mettre en place une infrastructure sécurisée et supervisée, avec des environnements de pré-production et de production.

## Architecture
L'application sera composée de trois tiers distincts :
- **Frontend** : Application web basée sur un template Vite.
- **Backend** : CMS WordPress.
- **Base de données** : Base de données hébergée sur un serveur dédié.

## Outils et Technologies
- **Cloud Provider** : Google Cloud Platform (GCP)
- **Infrastructure as Code (IaC)** : Terraform
- **Automatisation de la configuration** : Ansible
- **Orchestration de conteneurs** : Kubernetes (K8S)
- **Reverse Proxy / Load Balancer** : Traefik
- **Intégration Continue / Déploiement Continu (CI/CD)** : GitHub Actions
- **Supervision** : Prometheus et Grafana
- **Qualité du code** : SonarQube

## Environnements
Deux environnements seront mis en place :
- **Pré-production (preprod)** : Environnement de test et de validation.
- **Production (prod)** : Environnement de déploiement final.

## Objectifs du Projet
1.  **Automatisation du déploiement de l'infrastructure** :
    - Création de serveurs et déploiement de l'infrastructure via des scripts.
    - Sécurisation de l'infrastructure.
    - Mise en production dans le cloud.
2.  **Déploiement continu de l'application** :
    - Préparation d'un environnement de test.
    - Gestion du stockage de données.
    - Gestion des conteneurs.
    - Automatisation de la mise en production via une plateforme (GitHub Actions).
3.  **Supervision des services déployés** :
    - Mise en place de statistiques de service.
    - Exploitation d'une solution de supervision (Prometheus, Grafana).

## Sécurité
L'infrastructure sera configurée de manière restrictive pour éviter toute compromission, incluant :
- Droits d'accès stricts.
- Configuration de pare-feu.
- Utilisation de SSL/TLS.

## Qualité du Code
SonarQube sera intégré aux GitHub Actions pour assurer la qualité du code et l'intégration des vérifications.

## Déploiement
En cas de modification du code (à minima le frontend), un workflow GitHub Actions déclenchera le déploiement en production.

## Fichiers Clés
- `primordial-port-462408-q7-f0332c84ef23.json`: Clé de compte de service Google Cloud pour l'authentification.
- `todo.md`: Fichier de suivi des tâches du projet.



# trigger
# trigger
