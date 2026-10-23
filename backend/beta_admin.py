"""Local administration. Only invite creation prints a new plaintext invite."""
import argparse
import json
import os


def parser():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument('--data', help='Private account data directory (defaults to AETHERIA_ACCOUNT_DATA).')
    commands = arguments.add_subparsers(dest='command', required=True)
    invite = commands.add_parser('invite', help='Create a single-use expiring invite; copy the output once.')
    invite.add_argument('--hours', type=float, default=72)
    for command in ['grant', 'revoke']:
        commands.add_parser(command).add_argument('username')
    commands.add_parser('status', help='List access grants and invite counts without credentials.')
    return arguments


def run(argv=None):
    # Settings and database are initialized by main; kept separate for direct isolated tests.
    from backend.beta import create_invite, set_access, status
    arguments = parser().parse_args(argv)
    if arguments.command == 'invite':
        print(create_invite(arguments.hours))
    elif arguments.command in ('grant', 'revoke'):
        print(json.dumps(set_access(arguments.username, arguments.command == 'grant')))
    else:
        print(json.dumps(status()))


def main():
    arguments = parser().parse_args()
    if arguments.data:
        os.environ['AETHERIA_ACCOUNT_DATA'] = arguments.data
    # Loading config sets database credentials locally; do not start/reload services or migrate.
    from backend.service import load_config
    load_config()
    import django
    django.setup()
    try:
        run()
    except ValueError as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit('Beta administration failed. Check private configuration and applied migrations.') from None


if __name__ == '__main__':
    main()
