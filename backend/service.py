"""Private Windows-friendly local launcher. No secrets are passed in command lines."""
import argparse
import json
import logging
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

DATA = Path(os.environ.get('AETHERIA_ACCOUNT_DATA', Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'Aetheria' / 'online'))
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def load_config():
    DATA.mkdir(parents=True, exist_ok=True)
    path = DATA / 'config.json'
    if not path.exists():
        config = {'database': 'postgresql', 'db_name': 'aetheria', 'db_user': 'aetheria',
            'db_password': secrets.token_urlsafe(40), 'db_port': 55432,
            'django_secret': secrets.token_urlsafe(50), 'host': '127.0.0.1', 'port': 8780}
        with path.open('x', encoding='utf-8') as handle:
            json.dump(config, handle, indent=2)
    config = json.loads(path.read_text(encoding='utf-8-sig'))
    key_path = DATA / 'server.key'
    if not key_path.exists():
        key_path.write_text(secrets.token_urlsafe(48), encoding='utf-8')
    os.environ.setdefault('AETHERIA_SERVER_KEY', key_path.read_text(encoding='utf-8-sig').strip())
    os.environ.setdefault('AETHERIA_DJANGO_SECRET', config['django_secret'])
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
    if config['database'] == 'postgresql':
        for name, value in {'NAME': config['db_name'], 'USER': config['db_user'],
                            'PASSWORD': config['db_password'], 'PORT': config['db_port'], 'HOST': '127.0.0.1'}.items():
            os.environ.setdefault('AETHERIA_DB_'+name, str(value))
    elif config['database'] == 'sqlite-development':
        os.environ['AETHERIA_SQLITE_PATH'] = str(DATA / 'accounts.sqlite3')
    else:
        raise RuntimeError('Unsupported database configuration.')
    if config['host'] not in ('127.0.0.1', 'localhost', '::1'):
        if not os.environ.get('AETHERIA_PUBLIC_ORIGIN', '').startswith('https://'):
            raise RuntimeError('Remote account service requires AETHERIA_PUBLIC_ORIGIN=https://... and a TLS reverse proxy.')
        if config['database'] != 'postgresql':
            raise RuntimeError('Remote account service requires PostgreSQL.')
    return config


def run_private(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, creationflags=HIDDEN,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)


def ensure_postgres(config):
    if config['database'] != 'postgresql':
        return
    binary = Path(os.environ.get('AETHERIA_POSTGRES_BIN', DATA / 'postgresql-runtime' / 'pgsql' / 'bin'))
    if not (binary / 'pg_ctl.exe').exists():
        raise RuntimeError('Portable PostgreSQL is missing. Run tools/accounts.ps1 start to install the official EDB binaries.')
    pgdata = DATA / 'postgres-data'
    if not (pgdata / 'PG_VERSION').exists():
        pwfile = DATA / 'postgres-init-password.tmp'
        try:
            pwfile.write_text(config['db_password'], encoding='utf-8')
            run_private([binary / 'initdb.exe', '-D', pgdata, '-U', config['db_user'],
                         '-A', 'scram-sha-256', '--pwfile', pwfile, '-E', 'UTF8', '--locale=C'])
        finally:
            pwfile.unlink(missing_ok=True)
    privacy_config = ("\n# Aetheria private local database settings\nlisten_addresses = '127.0.0.1'\n"
                      "port = %d\nmax_connections = 30\nlog_statement = 'none'\n"
                      "log_min_error_statement = 'panic'\nlog_parameter_max_length_on_error = 0\n" % config['db_port'])
    pgconfig = pgdata / 'postgresql.conf'
    if privacy_config not in pgconfig.read_text(encoding='utf-8'):
        with pgconfig.open('a', encoding='utf-8') as handle:
            handle.write(privacy_config)
    status = subprocess.run([str(binary / 'pg_ctl.exe'), '-D', str(pgdata), 'status'],
        creationflags=HIDDEN, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if status.returncode:
        run_private([binary / 'pg_ctl.exe', '-D', pgdata, '-l', DATA / 'postgres.log', '-w', '-t', '30', 'start'])
    else:
        run_private([binary / 'pg_ctl.exe', '-D', pgdata, 'reload'])
    import psycopg
    from psycopg import sql
    with psycopg.connect(host='127.0.0.1', port=config['db_port'], user=config['db_user'],
                          password=config['db_password'], dbname='postgres', autocommit=True) as connection:
        exists = connection.execute('SELECT 1 FROM pg_database WHERE datname=%s', [config['db_name']]).fetchone()
        if not exists:
            connection.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(config['db_name'])))


def prepare():
    config = load_config()
    ensure_postgres(config)
    import django
    django.setup()
    from django.core.management import call_command
    call_command('migrate', interactive=False, verbosity=0)
    return config


def serve_app(config):
    """The same production WSGI settings are used by restart integration tests."""
    logging.disable(logging.CRITICAL)
    from django.core.wsgi import get_wsgi_application
    from waitress import serve
    proxy_options = {}
    if os.environ.get('AETHERIA_TRUSTED_PROXY'):
        proxy_options = {'trusted_proxy': os.environ['AETHERIA_TRUSTED_PROXY'],
            'trusted_proxy_count': 1,
            'trusted_proxy_headers': {'x-forwarded-proto', 'x-forwarded-host'}}
    serve(get_wsgi_application(), host=config['host'], port=config['port'],
          threads=4 if config['database'] == 'postgresql' else 1,
          max_request_body_size=262144, channel_timeout=30, connection_limit=64,
          **proxy_options)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    args = parser.parse_args()
    # Prevent a second service process (especially unsafe with SQLite development).
    DATA.mkdir(parents=True, exist_ok=True)
    lock = (DATA / 'service.lock').open('a+b')
    if not args.prepare and os.name == 'nt':
        import msvcrt
        lock.seek(0)
        lock.write(b'0')
        lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit('The account service is already running.')
    config = prepare()
    if args.prepare:
        return
    # Framework/request exception logs are intentionally disabled; only fixed startup
    # and status messages are retained. Credentials and full saves never enter logs.
    pidfile = DATA / 'service.json'
    pidfile.write_text(json.dumps({'pid': os.getpid(), 'repo': str(Path(__file__).resolve().parent.parent),
                                  'port': config['port'], 'database': config['database']}), encoding='utf-8')
    try:
        serve_app(config)
    finally:
        pidfile.unlink(missing_ok=True)
        lock.close()


if __name__ == '__main__':
    main()
