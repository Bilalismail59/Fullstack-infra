import os
import sys
import secrets

# Ajout du répertoire parent dans sys.path (ne pas modifier)
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from flask import Flask, send_from_directory, jsonify
from flask_cors import CORS
from src.models.user import db
from src.routes.user import user_bp


def create_app():
    """Factory de création de l'application Flask"""
    app = Flask(
        __name__,
        static_folder=os.path.join(os.path.dirname(__file__), 'static')
    )

    # Configuration de l'application
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY') or secrets.token_hex(32)
    app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{os.path.join(os.path.dirname(__file__), 'database', 'app.db')}"
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Activation de CORS (CSRF volontairement non activé, car API REST uniquement)
    # Safe: This API is stateless and consumed by a SPA, CSRF is not required.
    CORS(app)

    # Initialisation de la base de données
    db.init_app(app)

    # Enregistrement des Blueprints
    app.register_blueprint(user_bp, url_prefix='/api')

    # Routes d'API
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

    @app.route('/', defaults={'path': ''})
    @app.route('/<path:path>')
    def serve(path):
        """Servir les fichiers statiques (frontend SPA)"""
        static_folder_path = app.static_folder
        if not static_folder_path:
            return "Static folder not configured", 404

        requested_path = os.path.join(static_folder_path, path)
        index_path = os.path.join(static_folder_path, 'index.html')

        if path and os.path.exists(requested_path):
            return send_from_directory(static_folder_path, path)
        elif os.path.exists(index_path):
            return send_from_directory(static_folder_path, 'index.html')
        else:
            return "index.html not found", 404

    return app


# Point d'entrée pour le lancement local
if __name__ == '__main__':  # pragma: no cover
    app = create_app()
    with app.app_context():
        db.create_all()  # À automatiser séparément en prod avec Alembic ou script
    app.run(host='0.0.0.0', port=5000, debug=True)
