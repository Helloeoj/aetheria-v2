"""Distribution regressions: source exclusion, PCK versions and public-only profile."""
import io
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import beta_package as package


class PackageTests(unittest.TestCase):
    def test_source_server_developer_tools_and_secrets_are_excluded(self):
        for path in ['scripts/dev_tools/check.gd', 'scripts/server/server_main.gd',
                     'network/world_host.gd', 'network/world_host.gd.uid',
                     'network/server_bootstrap.gd', 'scenes/network/WorldServer.tscn',
                     'tools/sentinel.py', 'data/server.key', 'data/private.pem',
                     'docs/source.md', 'data/side_fit_candidate_validation.json']:
            self.assertTrue(package.excluded(Path(path)), path)
        for path in ['scripts/main.gd', 'Assets/Maps/Tavern/map.png',
                     'network/online_world_view.gd', 'data/items.json']:
            self.assertFalse(package.excluded(Path(path)), path)

    def test_profile_does_not_accept_secrets_or_plaintext_endpoint(self):
        profile = {'schema': 1, 'release_id': 'beta-1', 'world_id': 'world-1',
                   'account_url': 'https://beta.example.com', 'world_host': 'relay.example.com',
                   'world_port': 30000, 'tls_name': 'aetheria-beta'}
        package.validate_profile(profile)
        for changes in [{'account_url': 'http://beta.example.com'}, {'server_key': 'secret'},
                        {'account_url': 'https://name:secret@example.com'}, {'world_port': 1.5},
                        {'world_host': '../local'}, {'release_id': '../release'}]:
            with self.assertRaises(ValueError):
                package.validate_profile(dict(profile, **changes))

    def test_pack_audit_reads_embedded_v2_v3_and_rejects_raw_scripts(self):
        def pack(version, paths):
            entries = io.BytesIO()
            entries.write(struct.pack('<I', len(paths)))
            for path in paths:
                raw = path.encode()
                entries.write(struct.pack('<I', len(raw)) + raw + b'\0' * 36)
            header = b'GDPC' + struct.pack('<IIII', version, 4, 5, 1) + struct.pack('<IQ', 0, 0)
            header += struct.pack('<Q', 40) if version == 3 else b'\0' * 64
            data = header + entries.getvalue()
            return b'fake-executable' + data + struct.pack('<Q', len(data)) + b'GDPC'
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'Aetheria.exe'
            for version in (2, 3):
                good = ['res://data/beta_client.json', 'res://scripts/main.gdc']
                target.write_bytes(pack(version, good))
                self.assertEqual(package.audit(target)['resources'], 2)
                for bad in ['res://network/world_host.gdc', 'res://scripts/main.gd',
                            'res://tools/sentinel.py', 'res://scripts/dev_tools/probe.gdc']:
                    target.write_bytes(pack(version, good + [bad]))
                    with self.assertRaises(ValueError):
                        package.audit(target)


if __name__ == '__main__':
    unittest.main()
