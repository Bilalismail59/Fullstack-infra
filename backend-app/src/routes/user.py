from flask import Blueprint, jsonify, request
from src.models.user import User, db
from werkzeug.exceptions import BadRequest, NotFound

user_bp = Blueprint('user', __name__)

@user_bp.route('/users', methods=['GET'])
def get_users():
    """Get all users"""
    users = db.session.query(User).all()
    return jsonify([user.to_dict() for user in users]), 200

@user_bp.route('/users', methods=['POST'])
def create_user():
    """Create a new user"""
    if not request.is_json:
        raise BadRequest('Request must be JSON')

    data = request.get_json()
    if not data or 'username' not in data or 'email' not in data:
        raise BadRequest('Missing required fields: username and email')

    if db.session.query(User).filter_by(email=data['email']).first():
        raise BadRequest('Email already exists')

    try:
        user = User(username=data['username'], email=data['email'])
        db.session.add(user)
        db.session.commit()
        return jsonify(user.to_dict()), 201
    except Exception as e:
        db.session.rollback()
        raise BadRequest(f'Error creating user: {str(e)}')

@user_bp.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get a specific user by ID"""
    user = db.session.get(User, user_id)
    if not user:
        raise NotFound('User not found')
    return jsonify(user.to_dict()), 200

@user_bp.route('/users/<int:user_id>', methods=['PUT'])
def update_user(user_id):
    """Update a user by ID"""
    if not request.is_json:
        raise BadRequest('Request must be JSON')

    user = db.session.get(User, user_id)
    if not user:
        raise NotFound('User not found')

    data = request.get_json()
    if not data:
        raise BadRequest('No data provided')

    try:
        if 'username' in data:
            user.username = data['username']
        if 'email' in data:
            existing_user = db.session.query(User).filter(User.id != user_id, User.email == data['email']).first()
            if existing_user:
                raise BadRequest('Email already in use by another user')
            user.email = data['email']

        db.session.commit()
        return jsonify(user.to_dict()), 200
    except Exception as e:
        db.session.rollback()
        raise BadRequest(f'Error updating user: {str(e)}')

@user_bp.route('/users/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):
    """Delete a user by ID"""
    user = db.session.get(User, user_id)
    if not user:
        raise NotFound('User not found')

    try:
        db.session.delete(user)
        db.session.commit()
        return '', 204
    except Exception as e:
        db.session.rollback()
        raise BadRequest(f'Error deleting user: {str(e)}')
