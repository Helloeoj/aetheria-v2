"""Backup failure handling and private recovery bundle contract."""
import importlib.util
import json
import tempfile
import unittest
import os
import subprocess
import uuid
import zipfile
import hashlib
from pathlib import Path
from unittest.mock import patch


class ServerOpsTests(unittest.TestCase):
    def test_backup_includes_recovery_files_and_never_publishes_failed_dump(self):
        spec = importlib.util.spec_from_file_location('server_ops', Path(__file__).with_name('server_ops.py'))
        self.assertIsNotNone(spec)
        ops = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ops)
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory)
            (data / 'config.json').write_text(json.dumps({'database':'postgresql', 'db_name':'test', 'db_user':'test', 'db_password':'private', 'db_port':55432}))
            (data / 'server.key').write_text('private-world-key')
            with patch.object(ops, 'dump_database', side_effect=RuntimeError('dump failed')):
                with self.assertRaises(RuntimeError):
                    ops.backup(data)
            self.assertEqual(list((data / 'backups').glob('*.zip')), [])

    @unittest.skipUnless(os.environ.get('AETHERIA_BACKUP_INTEGRATION') == '1', 'explicit local database integration')
    def test_real_backup_restores_into_disposable_database(self):
        import server_ops as ops
        import psycopg
        from psycopg import sql
        config = json.loads((ops.DATA / 'config.json').read_text(encoding='utf-8-sig'))
        bundle = ops.backup()
        database = 'backup_verify_' + uuid.uuid4().hex
        connection = dict(host='127.0.0.1', port=config['db_port'], user=config['db_user'], password=config['db_password'])
        with tempfile.TemporaryDirectory(dir=ops.DATA / 'backups') as temporary:
            with zipfile.ZipFile(bundle) as archive:
                self.assertTrue({'database.dump','config.json','server.key','manifest.json'} <= set(archive.namelist()))
                dump = Path(temporary) / 'database.dump'
                dump.write_bytes(archive.read('database.dump'))
                manifest = json.loads(archive.read('manifest.json'))
                self.assertEqual(hashlib.sha256(dump.read_bytes()).hexdigest(), manifest['database_sha256'])
            with psycopg.connect(**connection, dbname='postgres', autocommit=True) as admin:
                admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(database)))
                try:
                    binary = ops.DATA / 'postgresql-runtime/pgsql/bin/pg_restore.exe'
                    result = subprocess.run([str(binary), '-h','127.0.0.1','-p',str(config['db_port']),'-U',config['db_user'],'-d',database,'--exit-on-error',str(dump)], env=ops.pg_environment(config), capture_output=True, creationflags=ops.HIDDEN)
                    self.assertEqual(result.returncode, 0, 'Disposable database restore failed')
                    with psycopg.connect(**connection, dbname=database) as restored:
                        self.assertGreater(restored.execute('SELECT count(*) FROM accounts_account').fetchone()[0], 0)
                        self.assertGreater(restored.execute('SELECT count(*) FROM accounts_character').fetchone()[0], 0)
                        self.assertGreater(restored.execute('SELECT count(*) FROM accounts_journal').fetchone()[0], 0)
                finally:
                    admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(database)))


if __name__ == '__main__':
    unittest.main()
