# backend-app/tests/test_user.py
from src.models.user import db, User

def test_get_users(client):
    with client.application.app_context():
        db.session.add(User(username="testuser", email="test@example.com"))
        db.session.commit()

    response = client.get("/api/users")
    assert response.status_code == 200
    users = response.get_json()
    assert isinstance(users, list)
    assert any(user["username"] == "testuser" for user in users)

def test_create_user(client):
    payload = {"username": "Bilal", "email": "bilal@example.com"}
    response = client.post("/api/users", json=payload)
    assert response.status_code == 201
    data = response.get_json()
    assert data["username"] == "Bilal"
    assert data["email"] == "bilal@example.com"

def test_update_user(client):
    with client.application.app_context():
        user = User(username="update_me", email="old@example.com")
        db.session.add(user)
        db.session.commit()
        user_id = user.id

    payload = {"username": "updated_name", "email": "new@example.com"}
    response = client.put(f"/api/users/{user_id}", json=payload)
    assert response.status_code == 200
    data = response.get_json()
    assert data["username"] == "updated_name"
    assert data["email"] == "new@example.com"

def test_delete_user(client):
    with client.application.app_context():
        user = User(username="delete_me", email="del@example.com")
        db.session.add(user)
        db.session.commit()
        user_id = user.id

    response = client.delete(f"/api/users/{user_id}")
    assert response.status_code == 204
    assert response.data == b""