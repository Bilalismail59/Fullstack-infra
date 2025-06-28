#  Projet de Déploiement Full Stack sur Google Cloud

Ce projet a pour objectif de déployer une application full stack avec une architecture trois tiers sur **Google Cloud Platform (GCP)**. L’objectif est de mettre en place une **infrastructure automatisée, sécurisée et supervisée**, avec deux environnements : **pré-production** et **production**.

---

##  Architecture

L'application est composée de trois couches distinctes :

-  **Frontend** : Application web React basée sur Vite
-  **Backend** : CMS WordPress conteneurisé
-  **Base de données** : MariaDB déployée dans un conteneur dédié

---

##  Outils et Technologies

| Catégorie              | Outils utilisés                               |
|------------------------|-----------------------------------------------|
| Cloud Provider         | Google Cloud Platform (GCP)                   |
| Infrastructure as Code | Terraform                                     |
| Configuration système  | Ansible                                       |
| Conteneurisation       | Docker + Kubernetes (K8s)                     |
| Load Balancer / Proxy  | Traefik                                       |
| CI/CD                  | GitHub Actions                                |
| Supervision            | Prometheus, Grafana, Netdata                  |
| Qualité du code        | SonarQube (via SonarCloud)                    |

---

##  Environnements

-  **Pré-production** : pour les tests et la validation
-  **Production** : pour la mise en ligne officielle

---

##  Objectifs du Projet

###  1. Automatisation de l’Infrastructure
- Déploiement via Terraform + Ansible
- Sécurisation par firewall, users limités, etc.
- Infrastructure scalable sur GCP

###  2. Déploiement Continu (CI/CD)
- Workflows GitHub Actions : build → test → deploy
- Gestion du stockage et des volumes persistants
- Docker Compose (en local) / K8s (en cloud)

###  3. Supervision et Observabilité
- Dashboards Prometheus + Grafana
- Alerting basique avec Alertmanager
- Netdata pour la supervision système

---

##  Sécurité

- Accès SSH restreint et surveillé
- Séparation des environnements
- Pare-feu strict (GCP VPC)
- SSL/TLS activé via Traefik
- Scan de vulnérabilités via OWASP ZAP *(à venir)*

---

##  Qualité du Code

- Intégration continue de SonarCloud dans les workflows
- Analyse de la couverture de tests avec `pytest` + `coverage`
- Revue des hotspots de sécurité

>  Qualité actuelle : **Passed** avec 0 bugs, 3 code smells, 13 security hotspots

---

##  Déploiement Automatisé

- Tout **push sur `main`** déclenche une analyse + déploiement
- Les workflows CI/CD automatisent :
  - L’analyse SonarCloud
  - Les tests unitaires
  - Le déploiement sur GCP via SSH + Docker/K8s

---

##  Fichiers Clés

| Fichier                            | Description                                      |
|-----------------------------------|--------------------------------------------------|
| `primordial-port-462408-*.json`  | Clé d’authentification GCP (service account)     |
| `todo.md`                         | Liste des tâches restantes                       |
| `.github/workflows/deploy.yml`   | Déploiement GitHub Actions                       |
| `terraform/`                      | Code IaC pour l’infra (VPC, instances, etc.)     |
| `ansible/`                        | Playbooks de configuration                       |
| `preprod/` et `prod/`            | Déploiement des services en environnements isolés|

---

##  Badges de Qualité (SonarCloud)

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=Bilalismail59_Fullstack-infra&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=Bilalismail59_Fullstack-infra)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=Bilalismail59_Fullstack-infra&metric=coverage)](https://sonarcloud.io/summary/new_code?id=Bilalismail59_Fullstack-infra)
[![Maintainability](https://sonarcloud.io/api/project_badges/measure?project=Bilalismail59_Fullstack-infra&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=Bilalismail59_Fullstack-infra)



---

##  Prochaines Améliorations

- [ ]  Scanner OWASP ZAP en CI
- [ ]  Ajout de tests e2e
- [ ]  Alertes Prometheus + Email
- [ ]  Génération auto de documentation technique

---

##  Auteur

**Ismail BILALI Issa Iyawa**  
Administrateur Systèmes DevOps  
 ismobilal@gmail.com

---

