# Makefile pour simplifier les commandes Docker Compose

.PHONY: help build up down logs clean test dev monitoring sonarqube

# Variables
COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
TEST_COMPOSE_FILE = docker-compose.test.yml
MONITORING_COMPOSE_FILE = docker-compose.monitoring.yml
SONARQUBE_COMPOSE_FILE = docker-compose.sonarqube.yml

help: ## Afficher l'aide
	@echo "Commandes disponibles :"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Construire toutes les images
	docker compose -f $(COMPOSE_FILE) build

up: ## Démarrer l'environnement de production
	docker compose -f $(COMPOSE_FILE) up -d
	@echo "Services démarrés :"
	@echo "- Frontend: http://localhost:3000"
	@echo "- Backend: http://localhost:5000"
	@echo "- WordPress: http://localhost:wp"
	@echo "- Traefik Dashboard: http://localhost:8081"

down: ## Arrêter tous les services
	docker compose -f $(COMPOSE_FILE) down
	docker compose -f $(DEV_COMPOSE_FILE) down
	docker compose -f $(MONITORING_COMPOSE_FILE) down
	docker compose -f $(SONARQUBE_COMPOSE_FILE) down

logs: ## Voir les logs de tous les services
	docker compose -f $(COMPOSE_FILE) logs -f

dev: ## Démarrer l'environnement de développement
	docker compose -f $(DEV_COMPOSE_FILE) up -d
	@echo "Environnement de développement démarré :"
	@echo "- Frontend Dev: http://localhost:3000"
	@echo "- Backend Dev: http://localhost:5000"
	@echo "- PostgreSQL Dev : localhost:5432"
	@echo "- MailHog: http://localhost:8025"

monitoring: ## Démarrer la stack de monitoring
	docker compose -f $(MONITORING_COMPOSE_FILE) up -d
	@echo "Stack de monitoring démarrée :"
	@echo "- Prometheus: http://localhost:9090"
	@echo "- Grafana: http://localhost:3001 (admin/admin)"
	@echo "- Alertmanager: http://localhost:9093"

sonarqube: ## Démarrer SonarQube
	docker compose -f $(SONARQUBE_COMPOSE_FILE) up -d
	@echo "SonarQube démarré :"
	@echo "- SonarQube: http://localhost:9000 (admin/admin)"

test: ## Lancer tous les tests
	docker compose -f $(TEST_COMPOSE_FILE) --profile test up --build test-runner

scan: ## Lancer l'analyse SonarQube
	docker compose -f $(SONARQUBE_COMPOSE_FILE) --profile scanner up sonar-scanner

full: ## Démarrer tous les environnements
	make up
	make monitoring
	make sonarqube
	@echo "Tous les services sont démarrés !"

clean: ## Nettoyer complètement
	docker compose -f $(COMPOSE_FILE) down -v --rmi all
	docker compose -f $(DEV_COMPOSE_FILE) down -v --rmi all
	docker compose -f $(MONITORING_COMPOSE_FILE) down -v --rmi all
	docker compose -f $(SONARQUBE_COMPOSE_FILE) down -v --rmi all
	docker system prune -f

status: ## Voir le statut de tous les services
	@echo "=== Services Production ==="
	docker compose -f $(COMPOSE_FILE) ps
	@echo "\n=== Services Développement ==="
	docker compose -f $(DEV_COMPOSE_FILE) ps
	@echo "\n=== Services Monitoring ==="
	docker compose -f $(MONITORING_COMPOSE_FILE) ps
	@echo "\n=== Services SonarQube ==="
	docker compose -f $(SONARQUBE_COMPOSE_FILE) ps

restart: ## Redémarrer tous les services
	make down
	make up

backup: ## Sauvegarder les volumes
	docker run --rm -v fullstack_mysql_data:/data -v $(PWD)/backups:/backup alpine tar czf /backup/mysql_backup_$(shell date +%Y%m%d_%H%M%S).tar.gz -C /data .
	docker run --rm -v fullstack_wordpress_data:/data -v $(PWD)/backups:/backup alpine tar czf /backup/wordpress_backup_$(shell date +%Y%m%d_%H%M%S).tar.gz -C /data .

restore: ## Restaurer les volumes (spécifier BACKUP_FILE=filename)
	@if [ -z "$(BACKUP_FILE)" ]; then echo "Usage: make restore BACKUP_FILE=backup.tar.gz"; exit 1; fi
	docker run --rm -v fullstack_mysql_data:/data -v $(PWD)/backups:/backup alpine tar xzf /backup/$(BACKUP_FILE) -C /data

# Commandes de développement
dev-logs: ## Voir les logs de développement
	docker compose -f $(DEV_COMPOSE_FILE) logs -f

dev-shell-frontend: ## Shell dans le conteneur frontend de dev
	docker compose -f $(DEV_COMPOSE_FILE) exec frontend-dev sh

dev-shell-backend: ## Shell dans le conteneur backend de dev
	docker compose -f $(DEV_COMPOSE_FILE) exec backend-dev bash

# Commandes de monitoring
monitoring-logs: ## Voir les logs de monitoring
	docker compose -f $(MONITORING_COMPOSE_FILE) logs -f

grafana-reset: ## Réinitialiser Grafana
	docker compose -f $(MONITORING_COMPOSE_FILE) stop grafana
	docker volume rm fullstack_grafana_data
	docker compose -f $(MONITORING_COMPOSE_FILE) up -d grafana

# Commandes utiles
ps: ## Voir tous les conteneurs
	docker ps -a

images: ## Voir toutes les images
	docker images

volumes: ## Voir tous les volumes
	docker volume ls

networks: ## Voir tous les réseaux
	docker network ls

stats: ## Voir les statistiques des conteneurs
	docker stats
