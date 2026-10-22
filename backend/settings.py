"""Private account service; development data must live outside the checkout."""
import os
from pathlib import Path

SECRET_KEY = os.environ.get('AETHERIA_DJANGO_SECRET', 'test-only-never-use-in-production')
DEBUG = False
ALLOWED_HOSTS = os.environ.get('AETHERIA_ALLOWED_HOSTS', '127.0.0.1,localhost,testserver').split(',')
ROOT_URLCONF = 'backend.urls'
INSTALLED_APPS = ['backend.accounts']
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
USE_TZ = True
MIDDLEWARE = []
PASSWORD_HASHERS = ['django.contrib.auth.hashers.Argon2PasswordHasher']
DATA_UPLOAD_MAX_MEMORY_SIZE = 262144
DEFAULT_CHARSET = 'utf-8'
if os.environ.get('AETHERIA_DB_NAME'):
    DATABASES = {'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ['AETHERIA_DB_NAME'],
        'USER': os.environ.get('AETHERIA_DB_USER', 'aetheria'),
        'PASSWORD': os.environ.get('AETHERIA_DB_PASSWORD', ''),
        'HOST': os.environ.get('AETHERIA_DB_HOST', '127.0.0.1'),
        'PORT': os.environ.get('AETHERIA_DB_PORT', '55432'),
    }}
else:
    DATABASES = {'default': {'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.environ.get('AETHERIA_SQLITE_PATH', ':memory:'),
        'OPTIONS': {'timeout': 20}}}
