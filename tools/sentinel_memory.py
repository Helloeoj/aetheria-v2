"""Local project knowledge, versioned intent and process evidence. No AI requests."""
from __future__ import annotations
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import threading
import time
import uuid
from sentinel_process import ProcessGroup

HIDDEN = 0x08000000 if os.name == 'nt' else 0
EXTENSIONS = {'.gd', '.py', '.ps1', '.md', '.tscn', '.tres', '.godot', '.json', '.toml', '.cfg'}
SECRET = re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY|\bsk-[A-Za-z0-9_-]{20,}|(?:access_token|refresh_token|api_key|password)\s*[=:]\s*[\"\'][^\"\'\s]{12,}[\"\']', re.I)
STOP = set('a an the to of in is it and or for with how what does can i want add make please my game'.split())


def terms(text):
    return [s for s in re.findall(r'[a-z0-9]{2,}', text.lower().replace('_', ' ')) if s not in STOP][:32]


def safe_text(text):
    text = str(text).replace(str(Path.home()), '<user>').replace(str(Path.home()).replace('\\', '/'), '<user>')
    return SECRET.sub('[redacted credential]', text)


def safe_value(value):
    if isinstance(value,str): return safe_text(value)
    if isinstance(value,list): return [safe_value(item) for item in value]
    if isinstance(value,dict): return {key:safe_value(item) for key,item in value.items()}
    return value


def memory_path(project):
    key = hashlib.sha256(str(Path(project).resolve()).casefold().encode()).hexdigest()[:16]
    return Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'AetheriaSentinel' / 'projects' / key / 'memory.sqlite3'


class ProjectMemory:
    def __init__(self, project, path=None):
        self.project = Path(project).resolve()
        self.path = Path(path or memory_path(project))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(self.path, timeout=10, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        try:
            self.db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY,mtime INTEGER,size INTEGER,hash TEXT,details TEXT);
                CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(path UNINDEXED,line UNINDEXED,body,keywords,tokenize='porter unicode61');
                CREATE TABLE IF NOT EXISTS rules(id INTEGER PRIMARY KEY,key TEXT,text TEXT,status TEXT,created REAL,parent INTEGER);
                CREATE TABLE IF NOT EXISTS receipts(id TEXT PRIMARY KEY,body TEXT);
                CREATE TABLE IF NOT EXISTS checkpoints(id INTEGER PRIMARY KEY,request TEXT,status TEXT,body TEXT,created REAL);
            ''')
            prior = self.db.execute("SELECT value FROM metadata WHERE key='project'").fetchone()
            if prior and prior[0] != str(self.project):
                raise ValueError('This memory belongs to a different project. Choose its own memory file.')
            version = self.db.execute("SELECT value FROM metadata WHERE key='version'").fetchone()
            if version and version[0] != '1':
                raise ValueError('Unsupported project memory version; original database preserved.')
            with self.db:
                self.db.execute("INSERT OR IGNORE INTO metadata VALUES('project',?)", (str(self.project),))
                self.db.execute("INSERT OR IGNORE INTO metadata VALUES('version','1')")
        except Exception:
            self.db.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        with self.lock:
            self.db.close()

    def _paths(self):
        result = subprocess.run(['git', '-C', str(self.project), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                                capture_output=True, timeout=20, creationflags=HIDDEN, check=True)
        paths = []
        for name in set(result.stdout.decode('utf-8', errors='replace').split('\0')):
            path = Path(name)
            lower = name.lower()
            if not name or path.is_absolute() or '..' in path.parts or path.suffix.lower() not in EXTENSIONS:
                continue
            if path.parts[0] not in ('godot_client', 'tools', 'docs') and path.name not in ('AGENTS.md', 'README.md'):
                continue
            if any(part.startswith('.') or part.lower() in ('assets', 'art_sources', 'legacy', '__pycache__', 'node_modules', 'diagnostics', 'launches') for part in path.parts[:-1]):
                continue
            if any(word in path.name.lower() for word in ('credential', 'secret', '.env', 'accounts.dpapi', 'token.json', 'auth.json')):
                continue
            absolute = self.project / path
            try:
                # Resolve every parent as well: junctions/symlinked directories may escape.
                if absolute.is_symlink() or not absolute.resolve().is_relative_to(self.project) or absolute.stat().st_size > 512_000:
                    continue
            except OSError:
                continue
            paths.append(path.as_posix())
        if len(paths) > 12000:
            raise ValueError('Project exceeds the 12,000 source-file index limit. Narrow the project first.')
        return sorted(paths)

    def refresh(self):
        with self.lock:
            paths = self._paths()
            known = {r['path']: dict(r) for r in self.db.execute('SELECT * FROM files')}
            counts = {'files': 0, 'read': 0, 'updated': 0, 'removed': 0, 'skipped': 0}
            with self.db:
                retained = set()
                for name in paths:
                    absolute = self.project / name
                    old = known.get(name)
                    try:
                        stat = absolute.stat()
                        if old and (old['mtime'], old['size']) == (stat.st_mtime_ns, stat.st_size):
                            retained.add(name)
                            continue
                        data = absolute.read_bytes()
                        counts['read'] += 1
                        if b'\0' in data:
                            raise ValueError('Binary source')
                        text = data.decode('utf-8-sig')
                        if SECRET.search(text):
                            raise ValueError('Credential-like source')
                    except (OSError, ValueError):
                        counts['skipped'] += 1
                        continue
                    digest = hashlib.sha256(data).hexdigest()
                    if not old or old['hash'] != digest:
                        self.db.execute('DELETE FROM chunks WHERE path=?', (name,))
                        lines = text.splitlines()
                        details = {'symbols': re.findall(r'^\s*(?:func|def|class|class_name)\s+(\w+)', text, re.M),
                                   'resources': re.findall(r'res://[^\s\"\')]+', text)[:100]}
                        for start in range(0, len(lines), 36):
                            body = '\n'.join(lines[start:start + 36])[:3500]
                            self.db.execute('INSERT INTO chunks VALUES(?,?,?,?)',
                                            (name, start + 1, body, name.replace('/', ' ').replace('_', ' ')))
                        counts['updated'] += 1
                    else:
                        details = json.loads(old['details'])
                    self.db.execute('INSERT OR REPLACE INTO files VALUES(?,?,?,?,?)',
                                    (name, stat.st_mtime_ns, stat.st_size, digest, json.dumps(details)))
                    retained.add(name)
                for name in known.keys() - retained:
                    self.db.execute('DELETE FROM chunks WHERE path=?', (name,))
                    self.db.execute('DELETE FROM files WHERE path=?', (name,))
                    counts['removed'] += 1
                counts['files'] = len(retained)
            return counts

    def _current(self, name):
        row = self.db.execute('SELECT mtime,size FROM files WHERE path=?', (name,)).fetchone()
        try:
            path = self.project / name
            stat = path.stat()
            return row and not path.is_symlink() and path.resolve().is_relative_to(self.project) and (row[0], row[1]) == (stat.st_mtime_ns, stat.st_size)
        except OSError:
            return False

    def search(self, query, limit=8):
        words = terms(query)
        if not words:
            return []
        with self.lock:
            rows = self.db.execute('SELECT path,line,body AS text,bm25(chunks,0,0,1,2) AS rank FROM chunks WHERE chunks MATCH ? ORDER BY rank LIMIT 300',
                                   (' OR '.join('"' + s + '"' for s in words),)).fetchall()
            seeking_tests = bool(set(words) & {'test','tests','testing','smoke','regression','validate'})
            seeking_design = bool(set(words) & {'design','rule','rules','planned','roadmap','proposal'})
            def score(row):
                path_words = set(terms(row['path']))
                matches = len(set(words) & set(terms(row['text'][:3500])))
                value = matches * 3 + len(set(words) & path_words) * 5 - row['rank']
                is_test = '/dev_tools/' in row['path'] or '/test_' in row['path'] or '_smoke.' in row['path']
                if is_test: value += 10 if seeking_tests else -16
                if '/docs/' in row['path'] or row['path'].startswith('docs/'):
                    value += 8 if seeking_design else -6
                return value
            rows = sorted(rows, key=score, reverse=True)
            result, per_file = [], {}
            for row in rows:
                name = row['path']
                if per_file.get(name, 0) >= 2 or not self._current(name):
                    continue
                result.append(dict(row))
                per_file[name] = per_file.get(name, 0) + 1
                if len(result) >= max(1, min(limit, 20)):
                    break
            return result

    def context(self, query, max_chars=12000):
        sections = []
        for row in self.search(query):
            sections.append(f"Observed source: {row['path']}:{row['line']}\n{row['text']}")
        return '\n\n'.join(sections)[:max(0, min(max_chars, 24000))]

    def snapshot(self):
        self.refresh()
        with self.lock:
            hashes = list(map(tuple, self.db.execute('SELECT path,hash FROM files ORDER BY path')))
            return hashlib.sha256(json.dumps(hashes).encode()).hexdigest()

    def propose_rule(self, key, text):
        key, text = key.strip(), text.strip()
        if not key or not text or len(key) > 100 or len(text) > 3000:
            raise ValueError('A rule needs a short topic and 1–3000 characters of text.')
        if SECRET.search(text):
            raise ValueError('Remove credential-like content from the rule.')
        with self.lock, self.db:
            return self.db.execute('INSERT INTO rules(key,text,status,created) VALUES(?,?,?,?)', (key, text, 'proposed', time.time())).lastrowid

    def approve_rule(self, identity):
        with self.lock, self.db:
            row = self.db.execute('SELECT * FROM rules WHERE id=?', (identity,)).fetchone()
            if not row or row['status'] != 'proposed':
                raise ValueError('Select a proposed rule to approve.')
            self.db.execute("UPDATE rules SET status='superseded' WHERE key=? AND status='approved'", (row['key'],))
            self.db.execute("UPDATE rules SET status='approved' WHERE id=?", (identity,))

    def rollback_rule(self, identity):
        with self.lock, self.db:
            row = self.db.execute('SELECT * FROM rules WHERE id=?', (identity,)).fetchone()
            if not row or row['status'] not in ('superseded', 'approved'):
                raise ValueError('Only a previously approved rule can be restored.')
            self.db.execute("UPDATE rules SET status='superseded' WHERE key=? AND status='approved'", (row['key'],))
            return self.db.execute("INSERT INTO rules(key,text,status,created,parent) VALUES(?,?,'approved',?,?)",
                                   (row['key'], row['text'], time.time(), identity)).lastrowid

    def rules(self):
        with self.lock:
            return [dict(row) for row in self.db.execute("SELECT * FROM rules WHERE status='approved' ORDER BY key")]

    def rule_history(self):
        with self.lock:
            return [dict(row) for row in self.db.execute('SELECT * FROM rules ORDER BY id DESC')]

    def preferences(self):
        with self.lock:
            row = self.db.execute("SELECT value FROM metadata WHERE key='preferences'").fetchone()
            return json.loads(row[0]) if row else {}

    def save_preferences(self, value):
        if not isinstance(value, dict) or any(k not in ('tokens','seconds','mode','model','effort','credits') for k in value):
            raise ValueError('Unsupported assistant preference.')
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO metadata VALUES('preferences',?)", (json.dumps(value),))

    def validate(self, argv, timeout=120, cancel=None):
        if not isinstance(argv, list) or not argv or not all(isinstance(s, str) and s for s in argv):
            raise ValueError('Validation must be a nonempty JSON array of executable and arguments.')
        before = self.snapshot()
        started = time.time()
        with tempfile.TemporaryFile() as output:
            process = subprocess.Popen(argv, cwd=self.project, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=HIDDEN, start_new_session=os.name != 'nt')
            group = ProcessGroup(process)
            timed_out = False
            cancelled = False
            try:
                deadline = time.monotonic() + max(1,min(timeout,600))
                while process.poll() is None:
                    cancelled = bool(cancel and cancel.is_set())
                    timed_out = time.monotonic() >= deadline
                    if cancelled or timed_out:
                        group.close()
                        if process.poll() is None: process.kill()
                        break
                    time.sleep(.05)
                code = process.wait(timeout=10)
            finally:
                group.close()
            output.seek(0, 2)
            size = output.tell()
            output.seek(max(0, size - 16000))
            tail = output.read().decode('utf-8', errors='replace')[-8000:]
        receipt = safe_value({'id': uuid.uuid4().hex, 'argv': argv, 'exit_code': code, 'timed_out': timed_out, 'cancelled':cancelled,
                   'output': tail, 'before': before, 'after': self.snapshot(), 'created': started})
        with self.lock, self.db:
            self.db.execute('INSERT INTO receipts VALUES(?,?)', (receipt['id'], json.dumps(receipt)))
        return receipt

    def checkpoint(self, request, status, body):
        # Agent prose is never promoted into a validation receipt.
        encoded = json.dumps(safe_value(body), ensure_ascii=False)
        if len(encoded) > 100000:
            raise ValueError('Checkpoint exceeds local evidence limit.')
        with self.lock, self.db:
            return self.db.execute('INSERT INTO checkpoints(request,status,body,created) VALUES(?,?,?,?)',
                                   (safe_text(request)[:8000], status, encoded, time.time())).lastrowid

    def update_checkpoint(self, identity, status, body):
        encoded=json.dumps(safe_value(body),ensure_ascii=False)
        if len(encoded)>100000: raise ValueError('Checkpoint exceeds local evidence limit.')
        with self.lock,self.db:
            self.db.execute('UPDATE checkpoints SET status=?,body=? WHERE id=?',(status,encoded,identity))

    def history(self, limit=30):
        digest = self.snapshot()
        with self.lock:
            result = []
            for item in self.db.execute('SELECT * FROM checkpoints ORDER BY id DESC LIMIT ?', (min(limit, 100),)):
                row = dict(item)
                row['body'] = json.loads(row['body'])
                receipt = row['body'].get('validation') or {}
                stored = self.db.execute('SELECT body FROM receipts WHERE id=?', (receipt.get('id', ''),)).fetchone()
                row['validation_passed'] = bool(row['status'] == 'completed' and stored and json.loads(stored[0]) == receipt
                                       and receipt.get('exit_code') == 0 and not receipt.get('timed_out') and not receipt.get('cancelled')
                                       and receipt.get('before') == receipt.get('after'))
                row['verified'] = row['validation_passed'] and receipt.get('after') == digest
                result.append(row)
            return result
