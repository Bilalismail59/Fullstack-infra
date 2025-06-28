# backend-app/tests/conftest.py
import pytest
from src.main import create_app
from src.models.user import db

@pytest.fixture
def app():
    """Fixture Flask app pour les tests"""
    app = create_app()
    app.config.update({
        'TESTING': True,
        'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:',
        'SQLALCHEMY_TRACK_MODIFICATIONS': False,
    })

    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()

@pytest.fixture
def client(app):
    """Fixture client HTTP pour les tests"""
    return app.test_client()
