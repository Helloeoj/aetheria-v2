"""Run account tests against a separate PostgreSQL test database, never live data."""
from backend.service import load_config, ensure_postgres


def main():
    config = load_config()
    ensure_postgres(config)
    import django
    django.setup()
    from django.core.management import call_command
    call_command('test', 'backend.accounts', verbosity=2, interactive=False)


if __name__ == '__main__':
    main()
