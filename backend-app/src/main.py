import os
import sys
from dotenv import load_dotenv
from flask import Flask, jsonify
from flask_cors import CORS
from src.models.user import db
from src.routes.user import user_bp

# Ajout du répertoire parent dans sys.path (ne pas modifier)
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

# Chargement des variables d'environnement depuis .env
load_dotenv()

def create_app():
    """Factory de création de l'application Flask"""
    app = Flask(__name__)

    # Sécurité : forcer la présence d'une clé secrète en variable d'env
    if not os.environ.get("SECRET_KEY"):
        raise RuntimeError("SECRET_KEY must be set in environment variables.")
    app.config['SECRET_KEY'] = os.environ["SECRET_KEY"]

    # Configuration de la base de données SQLite
    app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{os.path.join(os.path.dirname(__file__), 'database', 'app.db')}"
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Activer CORS pour toutes les routes (API REST uniquement)
    CORS(app)

    # Initialisation de la base de données
    db.init_app(app)

    # Enregistrement des routes (Blueprint)
    app.register_blueprint(user_bp, url_prefix='/api')

    # === ROUTES DE L'APPLICATION ===

    @app.route('/api/status')
    def status():
        """Statut de l'application"""
        return jsonify({
            'status': 'operational',
            'services': {
                'database': 'connected',
                'api': 'running',
                'version': '1.0.0'
            }
        })

    @app.route('/api/infrastructure')
    def infrastructure():
        """Informations sur l'infrastructure"""
        return jsonify({
            'environments': {
                'preprod': {'status': 'active', 'url': 'https://preprod.example.com'},
                'prod': {'status': 'deployed', 'url': 'https://prod.example.com'}
            },
            'services': [
                {'name': 'Frontend', 'status': 'running', 'health': 'healthy'},
                {'name': 'Backend', 'status': 'running', 'health': 'healthy'},
                {'name': 'Database', 'status': 'running', 'health': 'healthy'},
                {'name': 'Security', 'status': 'active', 'health': 'secure'},
                {'name': 'Monitoring', 'status': 'active', 'health': 'monitoring'},
                {'name': 'CI/CD', 'status': 'active', 'health': 'automated'}
            ],
            'technologies': [
                'Terraform', 'Ansible', 'Kubernetes', 'Docker',
                'Traefik', 'Prometheus', 'Grafana', 'SonarQube', 'GitHub Actions'
            ]
        })

    return app

# Point d'entrée pour le lancement local
if __name__ == '__main__':  # pragma: no cover
    app = create_app()
    with app.app_context():
        db.create_all()  # À automatiser en production
    app.run(host='0.0.0.0', port=5000, debug=True)
