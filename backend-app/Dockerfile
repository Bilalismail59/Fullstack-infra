# Dockerfile de développement pour le backend
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances système
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copier requirements.txt
COPY requirements.txt .

# Installer les dépendances Python
RUN pip install -r requirements.txt

# Installer des outils de développement
RUN pip install flask-debugtoolbar pytest pytest-cov black flake8

# Copier tout le code source
COPY . .

# Exposer le port utilisé par Flask
EXPOSE 5000

# Variables d'environnement nécessaires à Flask
ENV FLASK_ENV=development
ENV FLASK_DEBUG=1
ENV FLASK_APP=src/wsgi.py
ENV PYTHONPATH=/app

# Lancer l'application avec hot reload
CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
