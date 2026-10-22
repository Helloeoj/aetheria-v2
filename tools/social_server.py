"""Standalone Aetheria social service. Loopback by default; TLS for remote use."""
import argparse
import asyncio
import contextlib
import json
import logging
import os
from pathlib import Path
import ssl

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
from social_service import SocialService, SocialError, Store


class ChatServer:
    def __init__(self, store, capacity=50):
        self.service = SocialService(store, capacity=capacity)
        self.connections = {}
        self.pending = 0

    def dispatch(self, events):
        for identity, event in events:
            connection = self.connections.get(identity)
            if connection is None:
                continue
            queue, socket = connection
            if queue.full():
                asyncio.create_task(socket.close(1013, "Chat client is too slow"))
            else:
                queue.put_nowait(event)

    async def writer(self, identity, queue, socket):
        while True:
            event = await queue.get()
            if self.service.can_deliver(identity, event):
                try:
                    await asyncio.wait_for(socket.send(json.dumps(event, ensure_ascii=False)), 5)
                except asyncio.TimeoutError:
                    await socket.close(1013, "Chat client is too slow")
                    return

    async def handler(self, socket):
        identity = None
        writer = None
        if self.pending >= 32:
            await socket.close(1013, "Busy")
            return
        self.pending += 1
        pending = True
        try:
            raw = await asyncio.wait_for(socket.recv(), 8)
            hello = json.loads(raw)
            if not isinstance(raw, str) or not isinstance(hello, dict) or hello.get("v") != 1 or hello.get("op") != "hello" or set(hello) != {"v", "op", "name", "token"}:
                raise SocialError("Invalid chat handshake.")
            identity = self.service.join(hello["name"], hello["token"])
            self.pending -= 1
            pending = False
            queue = asyncio.Queue(maxsize=128)
            self.connections[identity] = (queue, socket)
            writer = asyncio.create_task(self.writer(identity, queue, socket))
            self.dispatch([(identity, {"type": "ready", "id": identity, "name": self.service.peers[identity]["name"]})])
            self.dispatch(self.service.snapshots())
            async for raw in socket:
                try:
                    if not isinstance(raw, str):
                        raise ValueError()
                    packet = json.loads(raw)
                except (ValueError, TypeError):
                    await socket.close(1008, "Invalid chat packet")
                    break
                self.dispatch(self.service.handle(identity, packet))
        except SocialError as error:
            await socket.send(json.dumps({"type": "error", "error": str(error)}))
            await socket.close(1008, "Chat profile unavailable")
        except (ConnectionClosed, asyncio.TimeoutError, ValueError, TypeError):
            pass
        finally:
            if pending:
                self.pending -= 1
            if identity is not None:
                self.connections.pop(identity, None)
                self.service.leave(identity)
                self.dispatch(self.service.snapshots())
            if writer:
                writer.cancel()
                with contextlib.suppress(asyncio.CancelledError, ConnectionClosed):
                    await writer


async def run(args):
    local = args.host in ("127.0.0.1", "::1", "localhost")
    tls = None
    if args.cert and args.key:
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(args.cert, args.key)
    elif not local:
        raise SystemExit("Remote chat requires --cert and --key. Plaintext is loopback-only.")
    args.database.parent.mkdir(parents=True, exist_ok=True)
    store = Store(args.database)
    chat = ChatServer(store, args.capacity)
    try:
        async with serve(chat.handler, args.host, args.port, ssl=tls, origins=[None],
                         max_size=8192, max_queue=16, write_limit=32768,
                         ping_interval=15, ping_timeout=30, close_timeout=3):
            print(f"Aetheria chat ready on {'wss' if tls else 'ws'}://{args.host}:{args.port}", flush=True)
            await asyncio.Future()
    finally:
        store.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    default = Path(os.environ.get("LOCALAPPDATA", Path.home() / ".local/share")) / "Aetheria" / "social.sqlite3"
    parser.add_argument("--database", type=Path, default=default)
    parser.add_argument("--capacity", type=int, default=50)
    parser.add_argument("--cert")
    parser.add_argument("--key")
    args = parser.parse_args()
    if not 1 <= args.capacity <= 10000 or not 1 <= args.port <= 65535:
        parser.error("Invalid capacity or port.")
    logging.getLogger("websockets").setLevel(logging.CRITICAL)
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
