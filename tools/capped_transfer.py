"""Run a publishing tool through a process-local, opaque HTTPS bandwidth cap.

Only the child inherits proxy settings. No router, adapter, firewall, DNS or
system-wide proxy settings are changed. TLS remains end-to-end.
"""
import argparse
import ipaddress
import os
import select
import socket
import socketserver
import subprocess
import threading
import time


class Rate:
    def __init__(self, bytes_per_second):
        if not 1 <= bytes_per_second <= 10000000:
            raise ValueError('Invalid transfer cap.')
        self.rate = bytes_per_second
        self.next = 0.0
        self.lock = threading.Lock()

    def wait(self, size):
        with self.lock:
            now = time.monotonic()
            due = max(self.next, now)
            self.next = due + size / self.rate
        delay = due - now
        if delay > 0:
            time.sleep(delay)


class Proxy(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False


class Tunnel(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(20)
        try:
            line = self.rfile.readline(4096).decode('ascii').strip().split()
            if len(line) != 3 or line[0] != 'CONNECT':
                return
            host, port = line[1].rsplit(':', 1)
            if port != '443' or not host or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in host):
                return
            headers_size = 0
            while True:
                header = self.rfile.readline(4096)
                headers_size += len(header)
                if headers_size > 8192:
                    return
                if header in (b'\r\n', b'\n', b''):
                    break
            addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
            if any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
                return
            with socket.create_connection((host, 443), timeout=20) as remote:
                self.connection.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
                self.connection.settimeout(30)
                remote.settimeout(30)
                while not self.server.stopping.is_set():
                    ready, _, _ = select.select([self.connection, remote], [], [], 1)
                    for source in ready:
                        data = source.recv(16384)
                        if not data:
                            return
                        self.server.rate.wait(len(data))
                        (remote if source is self.connection else self.connection).sendall(data)
        except (OSError, ValueError, UnicodeError):
            # Never log destinations, signed URLs, credentials or TLS bytes.
            return


def run(command, cap=500000):
    with Proxy(('127.0.0.1', 0), Tunnel) as server:
        server.rate = Rate(cap)
        server.stopping = threading.Event()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        proxy = 'http://127.0.0.1:' + str(server.server_address[1])
        environment = dict(os.environ, HTTPS_PROXY=proxy, HTTP_PROXY=proxy,
                           https_proxy=proxy, http_proxy=proxy, NO_PROXY='127.0.0.1,localhost,::1',
                           no_proxy='127.0.0.1,localhost,::1',
                           npm_config_proxy=proxy, npm_config_https_proxy=proxy)
        try:
            return subprocess.call(command, env=environment)
        finally:
            server.stopping.set()
            server.shutdown()
            thread.join(timeout=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bytes-per-second', type=int, default=500000)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A child command is required after --.')
    raise SystemExit(run(command, args.bytes_per_second))


if __name__ == '__main__':
    main()
