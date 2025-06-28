import pytest
from src.models.user import db, User

def test_create_user_missing_fields(client):
    response = client.post("/api/users", json={"username": "Bilal"})
    assert response.status_code == 400
    assert b"Missing required fields" in response.data

def test_create_user_existing_email(client):
    with client.application.app_context():
        db.session.add(User(username="existing", email="email@example.com"))
        db.session.commit()
    
    payload = {"username": "new", "email": "email@example.com"}
    response = client.post("/api/users", json=payload)
    assert response.status_code == 400
    assert b"Email already exists" in response.data

def test_update_user_not_found(client):
    payload = {"username": "New", "email": "new@example.com"}
    response = client.put("/api/users/999", json=payload)
    assert response.status_code == 404
    assert b"User not found" in response.data

def test_delete_user_not_found(client):
    response = client.delete("/api/users/999")
    assert response.status_code == 404
    assert b"User not found" in response.data

def test_get_user_not_found(client):
    response = client.get("/api/users/999")
    assert response.status_code == 404
    assert b"User not found" in response.data
