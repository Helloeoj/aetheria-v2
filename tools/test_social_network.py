"""Actual WebSocket transport and three independent Godot game clients."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import tempfile
from websockets.asyncio.server import serve
from websockets.asyncio.client import connect
from social_server import ChatServer
from social_service import Store


async def verify(godot, output):
    root = Path(__file__).resolve().parents[1]
    output.mkdir(parents=True, exist_ok=True)
    store = Store(output / "test.sqlite3")
    chat = ChatServer(store)
    processes, logs = [], []
    checks = 0
    async with serve(chat.handler, "127.0.0.1", 0, origins=[None], max_size=8192, ping_interval=15, ping_timeout=30) as server:
        url = f"ws://127.0.0.1:{server.sockets[0].getsockname()[1]}"
        async def wait_for(predicate, label, timeout=30):
            nonlocal checks
            deadline = asyncio.get_running_loop().time() + timeout
            while asyncio.get_running_loop().time() < deadline:
                if predicate():
                    checks += 1
                    print("PASS:", label, flush=True)
                    return
                for process in processes:
                    if process.returncode is not None:
                        raise AssertionError(f"Godot peer exited {process.returncode}: {label}")
                await asyncio.sleep(0.1)
            raise AssertionError(f"Timed out: {label}")

        def report(name):
            try:
                return json.loads((output / f"{name}.report.json").read_text(encoding="utf-8"))
            except (FileNotFoundError, json.JSONDecodeError, PermissionError):
                return {}

        counter = 0
        def command(name, op, **data):
            nonlocal counter
            counter += 1
            path = output / f"{name}.command.json"
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps({"sequence": counter, "op": op, "data": data}), encoding="utf-8")
            temporary.replace(path)

        def has_message(name, text):
            return any(event.get("text") == text for event in report(name).get("history", []))

        try:
            for name, x, y in [("Alice", 10, 10), ("Bob", 22, 26), ("Carol", 41, 10)]:
                config = {"name": name, "token": secrets.token_hex(32), "url": url, "x": x, "y": y,
                          "report": str(output / f"{name}.report.json"), "command": str(output / f"{name}.command.json")}
                path = output / f"{name}.config.json"
                path.write_text(json.dumps(config), encoding="utf-8")
                env = {**os.environ, "AETHERIA_SOCIAL_TEST_CONFIG": str(path),
                       "AETHERIA_DIAGNOSTICS_DIR": str(output / f"{name}.diagnostics")}
                log = (output / f"{name}.log").open("wb")
                logs.append(log)
                processes.append(await asyncio.create_subprocess_exec(godot, "--headless", "--log-file", str(output / f"{name}.native.log"), "--path", str(root / "godot_client"),
                    "--script", "res://scripts/dev_tools/social_network_peer.gd", "--", "--social-no-auto", env=env, stdout=log, stderr=log))
            await wait_for(lambda: all(report(n).get("connected") for n in ("Alice", "Bob", "Carol")), "Three Godot clients authenticate to a real server")
            assert all(report(n).get("name") == n for n in ("Alice", "Bob", "Carol")), "Chat ignored the admitted player's name"
            checks += 1
            await asyncio.sleep(0.7)
            command("Alice", "send", channel="global", text="Across the world")
            await wait_for(lambda: all(has_message(n, "Across the world") for n in ("Alice", "Bob", "Carol")), "Global reaches all three game clients")
            await wait_for(lambda: all("[Global] Alice: Across the world" in report(n).get("transcript", "") for n in ("Alice", "Bob", "Carol")), "Other players see the login name in rendered chat, not a generated nickname")
            command("Alice", "send", channel="local", text="Exactly twenty tiles")
            await wait_for(lambda: has_message("Bob", "Exactly twenty tiles"), "Local reaches the player exactly twenty tiles away")
            assert not has_message("Carol", "Exactly twenty tiles"), "Distant player heard local chat"
            checks += 1
            command("Alice", "send", channel="private", target="Bob", text="Only you can see this")
            await wait_for(lambda: has_message("Bob", "Only you can see this") and has_message("Alice", "Only you can see this"), "Private reaches only sender and intended recipient")
            assert not has_message("Carol", "Only you can see this"), "Private message leaked"
            checks += 1
            command("Bob", "friend_add", target="Alice")
            await wait_for(lambda: len(report("Bob").get("friends", [])) == 1, "Friends list updates in the game")
            command("Bob", "block_add", target="Alice")
            await wait_for(lambda: len(report("Bob").get("blocks", [])) == 1 and report("Bob").get("friends") == [], "Blocking atomically removes the friend")
            command("Alice", "send", channel="global", text="Filtered public message")
            await wait_for(lambda: has_message("Carol", "Filtered public message"), "Unblocked player still receives Global")
            assert not has_message("Bob", "Filtered public message"), "Blocked public message leaked"
            checks += 1
            command("Bob", "send", channel="private", target="Alice", text="Cannot contact blocked player")
            await wait_for(lambda: "unavailable" in report("Bob").get("status", ""), "Private messaging is blocked in the reverse direction")
            assert not has_message("Alice", "Cannot contact blocked player")
            checks += 1
            # Also exercise transport rejection before any profile is admitted.
            async with connect(url, proxy=None) as stranger:
                await stranger.send(json.dumps({"v": 1, "op": "send", "channel": "global", "text": "Spoof"}))
                rejected = json.loads(await stranger.recv())
                assert rejected["type"] == "error"
                checks += 1
            print(f"[Social network] {checks} checks, 0 failures", flush=True)
        finally:
            for name in ("Alice", "Bob", "Carol"):
                command(name, "quit")
            for process in processes:
                try:
                    await asyncio.wait_for(process.wait(), 5)
                except asyncio.TimeoutError:
                    process.terminate()
                    await process.wait()
            for log in logs:
                log.close()
            for name in ("Alice", "Bob", "Carol"):
                source = (output / f"{name}.log").read_text(encoding="utf-8", errors="replace")
                if "SCRIPT ERROR" in source or "ERROR:" in source:
                    raise AssertionError(f"Godot errors in {name}.log: {source}")
    store.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.output:
        output = args.output / ("run-" + secrets.token_hex(4))
        print(f"Validation evidence: {output}", flush=True)
        asyncio.run(verify(args.godot, output))
    else:
        with tempfile.TemporaryDirectory(prefix="aetheria-social-") as folder:
            asyncio.run(verify(args.godot, Path(folder)))


if __name__ == "__main__":
    main()
