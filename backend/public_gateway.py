"""Narrow loopback ingress for a free HTTPS Worker -> Tunnel -> account API route.

Never point a tunnel at the private account service. This process exposes only the
player API and authenticates its edge Worker before trusting a client IP.
"""
import hmac
import ipaddress
import json
import os
from pathlib import Path

PUBLIC_ROUTES = {
    '/api/register': 'POST', '/api/login': 'POST', '/api/logout': 'POST',
    '/api/character': 'GET', '/api/admit': 'POST', '/api/release': 'GET',
    '/health': 'GET',
}


def reject(start_response, status='404 Not Found'):
    payload = b'{"ok":false,"message":"Not available."}'
    start_response(status, [('Content-Type', 'application/json'),
                           ('Content-Length', str(len(payload))), ('Cache-Control', 'no-store')])
    return [payload]


def gateway(application, token, policy_loader):
    if not isinstance(token, str) or len(token) < 40:
        raise ValueError('A private ingress token is required.')

    def serve(environ, start_response):
        try:
            local = ipaddress.ip_address(environ.get('REMOTE_ADDR', '')).is_loopback
            supplied = environ.get('HTTP_X_AETHERIA_INGRESS', '')
            authorized = hmac.compare_digest(token.encode(), supplied.encode())
            remote = ipaddress.ip_address(environ.get('HTTP_X_AETHERIA_CLIENT_IP', ''))
            length = int(environ.get('CONTENT_LENGTH') or 0)
            enabled = policy_loader()['enabled'] is True
        except (ValueError, KeyError, TypeError, OSError):
            return reject(start_response)
        except Exception:
            return reject(start_response, '503 Service Unavailable')
        route = environ.get('PATH_INFO', '')
        if (not local or not authorized or not enabled or route not in PUBLIC_ROUTES
                or environ.get('REQUEST_METHOD') != PUBLIC_ROUTES[route]
                or environ.get('QUERY_STRING') or not 0 <= length <= 262144):
            return reject(start_response)
        # Build a new WSGI boundary, forwarding no internal key, cookie, host,
        # forwarded-proto or other caller-controlled proxy trust headers.
        clean = {key: value for key, value in environ.items() if not key.startswith('HTTP_')}
        clean.update({'REMOTE_ADDR': str(remote), 'HTTP_HOST': '127.0.0.1',
                      'SERVER_NAME': '127.0.0.1', 'wsgi.url_scheme': 'https'})
        if 'HTTP_AUTHORIZATION' in environ:
            clean['HTTP_AUTHORIZATION'] = environ['HTTP_AUTHORIZATION']
        return application(clean, start_response)
    return serve


def main():
    from backend.service import DATA, load_config
    load_config()
    import django
    django.setup()
    from backend.beta import load_policy
    from django.core.wsgi import get_wsgi_application
    from waitress import serve
    config = json.loads((DATA / 'ingress.json').read_text(encoding='utf-8-sig'))
    port = config.get('port', 8781)
    if type(port) is not int or not 1024 <= port <= 65535:
        raise SystemExit('Invalid private ingress port.')
    if not load_policy()['enabled']:
        raise SystemExit('Enable a validated beta policy before starting public ingress.')
    import logging
    logging.disable(logging.CRITICAL)
    app = gateway(get_wsgi_application(), config.get('token'), load_policy)
    (DATA / 'ingress-process.json').write_text(json.dumps({'pid': os.getpid(), 'port': port,
        'repo': str(Path(__file__).resolve().parents[1])}), encoding='utf-8')
    try:
        serve(app, host='127.0.0.1', port=port, threads=4, max_request_body_size=262144,
              channel_timeout=15, connection_limit=32, clear_untrusted_proxy_headers=True)
    finally:
        (DATA / 'ingress-process.json').unlink(missing_ok=True)


if __name__ == '__main__':
    main()
