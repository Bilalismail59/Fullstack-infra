import os
import tempfile
from unittest.mock import patch
import pytest
from src.main import create_app

def test_status_route(client):
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "operational"
    assert "database" in data["services"]
    assert "api" in data["services"]
    assert "version" in data["services"]

def test_infrastructure_route(client):
    response = client.get("/api/infrastructure")
    assert response.status_code == 200
    data = response.get_json()
    assert "environments" in data
    assert "services" in data
    assert "technologies" in data
    assert isinstance(data["technologies"], list)

def test_fallback_root_route(client):
    response = client.get("/")
    assert response.status_code in (200, 404)

def test_fallback_unknown_path(client):
    response = client.get("/does-not-exist")
    assert response.status_code in (200, 404)

def test_serve_static_folder(client):
    response = client.get("/")
    assert response.status_code in [200, 404]

def test_blueprint_is_registered(app):
    rules = [rule.rule for rule in app.url_map.iter_rules()]
    assert '/api/users' in rules

def test_app_configuration(app):
    assert app.config['SECRET_KEY'] is not None
    assert app.config['SQLALCHEMY_DATABASE_URI'].startswith("sqlite:///")
    assert app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] is False

def test_serve_static_folder_not_configured(app):
    original_static_folder = app._static_folder
    app._static_folder = None
    with app.test_client() as client:
        response = client.get('/')
        assert response.status_code == 404
        assert b"Static folder not configured" in response.data
    app._static_folder = original_static_folder

def test_serve_index_not_found(monkeypatch, app):
    monkeypatch.setattr("os.path.exists", lambda path: False)
    with app.test_client() as client:
        response = client.get("/any-path")
        assert response.status_code == 404
        assert b"index.html not found" in response.data

def test_static_index_file_served(app, tmp_path):
    index_file = tmp_path / "index.html"
    index_file.write_text("<html>Accueil</html>")
    app.static_folder = tmp_path
    with app.test_client() as client:
        response = client.get("/")
        assert response.status_code == 200
        assert b"Accueil" in response.data

def test_static_specific_file_served(app, tmp_path):
    static_file = tmp_path / "hello.txt"
    static_file.write_text("Bonjour !")
    app.static_folder = tmp_path
    with app.test_client() as client:
        response = client.get("/hello.txt")
        assert response.status_code == 200
        assert b"Bonjour" in response.data

def test_create_app_explicit():
    app = create_app()
    assert app is not None
    assert app.config['SECRET_KEY']

def test_create_app_initialization():
    app = create_app()
    assert app is not None
    assert app.static_folder.endswith("static")

def test_app_fails_without_secret_key(monkeypatch):
    monkeypatch.delenv("SECRET_KEY", raising=False)
    with pytest.raises(RuntimeError, match="SECRET_KEY must be set in environment variables."):
        create_app()