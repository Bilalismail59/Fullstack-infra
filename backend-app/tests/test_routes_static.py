import os
import pytest
from src.main import create_app

@pytest.fixture
def client():
    app = create_app()
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_root_route_index_not_found(client):
    # Simule l'absence de index.html
    index_path = os.path.join(client.application.static_folder, 'index.html')
    if os.path.exists(index_path):
        os.remove(index_path)

    response = client.get('/')
    assert response.status_code == 404
    assert b"index.html not found" in response.data

def test_serve_non_existing_static_file(client):
    response = client.get('/nonexistent-file.js')
    assert response.status_code == 404
    assert b"index.html not found" in response.data

def test_static_folder_is_none(monkeypatch):
    """Teste la route / avec app.static_folder = None (couvre ligne 81 de main.py)"""
    app = create_app()
    monkeypatch.setattr(app, "static_folder", None)
    with app.test_client() as client:
        response = client.get('/')
        assert response.status_code == 404
        assert b"Static folder not configured" in response.data
