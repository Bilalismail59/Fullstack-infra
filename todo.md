## Phase 1: Analyse des exigences et préparation de l'environnement
- [ ] Examiner en détail les exigences du projet.
- [ ] Préparer l'environnement de travail (installation des outils nécessaires, configuration des accès Google Cloud).
- [ ] Créer un fichier `README.md` pour le projet.

## Phase 2: Configuration de l'infrastructure as Code avec Terraform
- [ ] Définir l'architecture de l'infrastructure sur Google Cloud (VPC, sous-réseaux, instances, etc.).
- [x] Écrire les fichiers Terraform pour provisionner l'infrastructure.
- [x] Mettre en place les environnements `preprod` et `prod`.

## Phase 3: Configuration de l'automatisation avec Ansible
- [x] Créer les playbooks Ansible pour la configuration des serveurs (sécurité, installation des dépendances).
- [x] Gérer les utilisateurs et les droits d’accès.
- [x] Configurer le firewall et SSL.

## Phase 4: Développement des applications frontend et backend
- [x] Mettre en place un template Vite pour le frontend.
- [x] Installer et configurer WordPress pour le backend.

## Phase 5: Configuration de Kubernetes et des conteneurs
- [x] Conteneuriser les applications frontend et backend.
- [x] Écrire les manifestes Kubernetes pour le déploiement.
- [x] Configurer les déploiements, services et ingress.

## Phase 6: Configuration du reverse proxy et load balancer avec Traefik
- [x] Déployer Traefik sur Kubernetes.
- [x] Configurer Traefik pour le routage des requêtes vers le frontend et le backend.
- [ ] Mettre en place le load balancing.

## Phase 7: Mise en place de la supervision avec Grafana et Prometheus
- [x] Déployer Prometheus pour la collecte des métriques.
- [x] Déployer Grafana pour la visualisation des données.s.
- [ ] Configurer les tableaux de bord et les alertes.

## Phase 8: Configuration de SonarQube et intégration qualité
- [x] Déployer SonarQube.
- [ ] Intégrer SonarQube dans les GitHub Actions.

## Phase 9: Configuration des GitHub Actions pour le déploiement continu
- [x] Créer les workflows GitHub Actions pour le déploiement du frontend et du backend.
- [x] Automatiser le déploiement vers les environnements `preprod` et `prod`.

## Phase 10: Sécurisation de l'infrastructure
- [x] Appliquer les bonnes pratiques de sécurité (IAM, pare-feu, chiffrement).
- [x] Mettre en place des audits de sécurité réguliers.

## Phase 11: Tests et validation des environnements preprod et prod
- [x] Effectuer des tests fonctionnels et de performance.
- [x] Valider la conformité de l'infrastructure et des applications.

## Phase 12: Documentation finale et livraison
- [x] Rédiger la documentation complète du projet.
- [x] Livrer le projet et présenter les résultats.

