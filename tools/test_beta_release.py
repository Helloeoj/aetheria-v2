import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import beta_ops
import beta_release
import server_ops


class ReleaseTests(unittest.TestCase):
    def test_activation_requires_exact_completed_upload_and_version(self):
        state = {'channels': [{'name': 'windows-beta', 'uploadId': 42,
            'head': {'state': 'completed', 'userVersion': 'beta-2'}}]}
        self.assertTrue(beta_release.upload_ready(state, 42, 'beta-2'))
        self.assertFalse(beta_release.upload_ready(state, 43, 'beta-2'))
        self.assertFalse(beta_release.upload_ready(state, 42, 'beta-1'))
        state['channels'][0]['head']['state'] = 'processing'
        self.assertFalse(beta_release.upload_ready(state, 42, 'beta-2'))
        self.assertFalse(beta_release.upload_ready({'channels': []}, 42, 'beta-2'))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.data = Path(self.temporary.name)
        (self.data / 'beta-runtime').mkdir()
        self.settings = {'world_id': 'world-1', 'owner_username': 'owner', 'upload_id': 42,
            'account_url': 'https://beta.example', 'world_host': 'relay.example', 'world_port': 21777}
        beta_ops.write_json(self.data / 'beta-runtime/hosting.json', self.settings)
        self.old = {'exe': 'old-server.exe', 'repo': str(server_ops.REPO), 'schema': 1}
        beta_ops.write_json(self.data / 'server-build.json', self.old)
        beta_ops.write_json(self.data / 'world.json', {'release_id': 'beta-1'})
        beta_ops.write_json(self.data / 'beta.json', {'enabled': True, 'release_id': 'beta-1'})
        self.original = {name: (self.data / name).read_bytes()
                         for name in ('server-build.json', 'world.json', 'beta.json')}

    def export_server(self, command, **kwargs):
        executable = Path(command[-1])
        executable.write_bytes(b'server-runtime')
        executable.with_suffix('.pck').write_bytes(b'server-package')
        return subprocess.CompletedProcess(command, 0)

    def export_client(self, godot, profile, certificate, output):
        output.mkdir(parents=True, exist_ok=True)
        (output.parent / (output.name + '-validation')).mkdir(exist_ok=True)
        executable = output / 'Aetheria.exe'
        executable.write_bytes(b'client-package')
        metadata = {'schema': 1, 'release_id': profile['release_id'], 'executable': 'Aetheria.exe',
            'client_sha256': hashlib.sha256(b'client-package').hexdigest(), 'client_bytes': 14}
        beta_ops.write_json(output / 'release.json', metadata)
        return metadata

    def assert_old_selection(self):
        for name, content in self.original.items():
            self.assertEqual((self.data / name).read_bytes(), content, name)

    def run_release(self, *options, publish_error=None):
        real_build = server_ops.build
        def local_build(godot, **kwargs):
            return real_build(godot, data=self.data, **kwargs)
        with patch.object(beta_release, 'DATA', self.data), \
                patch.object(beta_release.beta_package, 'build', side_effect=self.export_client), \
                patch.object(server_ops, 'build', side_effect=local_build), \
                patch.object(server_ops.subprocess, 'run', side_effect=self.export_server), \
                patch.object(beta_release, 'publish', side_effect=publish_error), \
                patch.object(sys, 'argv', ['beta_release.py', '--godot', 'fake-godot',
                                         '--release', 'beta-2', *options]):
            beta_release.main()

    def test_build_only_preserves_active_server_world_and_policy(self):
        self.run_release()
        self.assert_old_selection()

    def test_failed_publication_preserves_active_server_world_and_policy(self):
        with self.assertRaisesRegex(RuntimeError, 'upload failed'):
            self.run_release('--publish', publish_error=RuntimeError('upload failed'))
        self.assert_old_selection()

    # These tests use disposable files; process, export, backup and upload boundaries
    # are replaced so the installed world and account service are never touched.
    def candidate(self):
        with patch.object(server_ops.subprocess, 'run', side_effect=self.export_server):
            return server_ops.build('fake-godot', data=self.data, release_id='beta-2')

    def client_pair(self, candidate):
        output = self.data / 'beta-builds/beta-2'
        metadata = self.export_client(None, {'release_id': 'beta-2'}, None, output)
        beta_release.seal_pair(output, metadata, candidate)
        return metadata

    def activation(self, candidate, *, stop_error=None, backup_error=None, write_error=False):
        metadata = self.client_pair(candidate)
        events = []
        def stop():
            self.assert_old_selection()
            events.append('stop')
            if stop_error:
                raise stop_error
        def backup():
            self.assertEqual(events, ['stop'])
            self.assert_old_selection()
            events.append('backup')
            if backup_error:
                raise backup_error
        def start(settings):
            events.append('start')
            server_ops.validate_startup(self.data)
            self.assertEqual(beta_ops.read_json(self.data / 'server-build.json')['exe'],
                             beta_ops.read_json(candidate)['exe'])
            self.assertEqual(beta_ops.read_json(self.data / 'world.json')['release_id'], 'beta-2')
            self.assertEqual(beta_ops.read_json(self.data / 'beta.json')['release_id'], 'beta-2')
        real_write = beta_ops.write_json
        def write(path, value):
            if write_error and path.name == 'beta.json':
                raise OSError('policy write failed')
            return real_write(path, value)
        with patch.object(beta_release, 'DATA', self.data), \
                patch.object(beta_ops, 'stop', side_effect=stop), \
                patch.object(server_ops, 'backup', side_effect=backup), \
                patch.object(beta_release, 'run'), \
                patch.object(beta_ops, 'start', side_effect=start), \
                patch.object(beta_ops, 'write_json', side_effect=write):
            beta_release.activate(self.settings, metadata, candidate)
        return events

    def test_development_build_still_selects_the_new_executable(self):
        with patch.object(server_ops.subprocess, 'run', side_effect=self.export_server):
            executable = server_ops.build('fake-godot', data=self.data)
        self.assertEqual(beta_ops.read_json(self.data / 'server-build.json')['exe'], str(executable))

    def test_activation_selects_exact_candidate_after_stop_and_backup(self):
        candidate = self.candidate()
        self.assertEqual(self.activation(candidate), ['stop', 'backup', 'start'])
        self.assertEqual(beta_ops.read_json(self.data / 'server-build.json'), beta_ops.read_json(candidate))
        self.assertFalse((self.data / 'beta-runtime/activation.pending').exists())

    def test_bad_candidate_or_wrong_release_rejected_before_stop(self):
        candidate = self.candidate()
        metadata = self.client_pair(candidate)
        for changes in ({'release_id': 'beta-3'}, {'pck_sha256': 'f' * 64}, {'exe_sha256': 'f' * 64}):
            original = beta_ops.read_json(candidate)
            beta_ops.write_json(candidate, dict(original, **changes))
            with patch.object(beta_ops, 'stop') as stop:
                with self.assertRaises(RuntimeError):
                    beta_release.activate(self.settings, metadata, candidate)
                stop.assert_not_called()
            beta_ops.write_json(candidate, original)
        self.assert_old_selection()

    def test_changed_package_cannot_be_resealed_as_same_candidate(self):
        candidate = self.candidate()
        executable = Path(beta_ops.read_json(candidate)['exe'])
        executable.with_suffix('.pck').write_bytes(b'changed-server-package')
        with self.assertRaises(RuntimeError):
            server_ops.verify_candidate(candidate, 'beta-2')
        with self.assertRaises(RuntimeError):
            server_ops.candidate_manifest(executable, 'beta-2')

    def test_failed_stop_and_failed_backup_preserve_old_selection(self):
        candidate = self.candidate()
        for failure in ({'stop_error': RuntimeError('save failed')},
                        {'backup_error': RuntimeError('backup failed')}):
            with self.assertRaises(RuntimeError):
                self.activation(candidate, **failure)
            self.assert_old_selection()

    def test_incomplete_activation_fails_closed_on_restart(self):
        candidate = self.candidate()
        with self.assertRaisesRegex(OSError, 'policy write failed'):
            self.activation(candidate, write_error=True)
        self.assertTrue((self.data / 'beta-runtime/activation.pending').exists())
        with self.assertRaises(RuntimeError):
            server_ops.validate_startup(self.data)
        # Even removing the interrupted-activation marker cannot hide mismatch.
        (self.data / 'beta-runtime/activation.pending').unlink()
        with self.assertRaises(RuntimeError):
            server_ops.validate_startup(self.data)

    def test_startup_rejects_policy_world_pointer_or_package_mismatch(self):
        candidate = self.candidate()
        selected = beta_ops.read_json(candidate)
        metadata = self.client_pair(candidate)
        beta_ops.write_json(self.data / 'server-build.json', selected)
        beta_ops.write_json(self.data / 'world.json', {'release_id': 'beta-2'})
        beta_ops.write_json(self.data / 'beta.json', {'enabled': True, 'release_id': 'beta-2',
            'client_sha256': metadata['client_sha256'], 'client_bytes': metadata['client_bytes']})
        server_ops.validate_startup(self.data)
        for name, changes in [('world.json', {'release_id': 'beta-1'}),
                              ('beta.json', {'release_id': 'beta-1'}),
                              ('beta.json', {'client_sha256': 'f' * 64}),
                              ('server-build.json', {'exe_sha256': 'f' * 64})]:
            original = beta_ops.read_json(self.data / name)
            beta_ops.write_json(self.data / name, dict(original, **changes))
            with self.assertRaises(RuntimeError):
                server_ops.validate_startup(self.data)
            beta_ops.write_json(self.data / name, original)
        Path(selected['exe']).with_suffix('.pck').write_bytes(b'modified')
        with self.assertRaises(RuntimeError):
            server_ops.validate_startup(self.data)

    def test_beta_start_rejects_mismatch_before_ingress_or_world_start(self):
        with patch.object(beta_ops, 'DATA', self.data), patch.object(beta_ops, 'online') as online, \
                patch.object(beta_ops, 'spawn') as spawn:
            with self.assertRaises(RuntimeError):
                beta_ops._start(self.settings)
            online.assert_not_called()
            spawn.assert_not_called()

    def test_normal_start_rejects_mismatch_before_account_start(self):
        import os
        # online.ps1 must fail before accounts.ps1 can create any account config.
        environment = dict(os.environ, LOCALAPPDATA=str(self.data))
        private = self.data / 'Aetheria/online'
        private.mkdir(parents=True)
        beta_ops.write_json(private / 'beta.json', {'enabled': True, 'release_id': 'beta-2'})
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(server_ops.REPO / 'tools/online.ps1'), 'start'],
            env=environment, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('release', result.stdout + result.stderr)
        self.assertFalse((private / 'config.json').exists())
    def reuse_fixture(self):
        import struct
        output = self.data / 'beta-builds/beta-2'
        output.mkdir(parents=True)
        entries = struct.pack('<I', 2)
        for name in ('res://data/beta_client.json', 'res://scripts/main.gdc'):
            raw = name.encode()
            entries += struct.pack('<I', len(raw)) + raw + b'\0' * 36
        package = b'GDPC' + struct.pack('<IIII', 2, 4, 5, 1) + struct.pack('<IQ', 0, 0) + b'\0' * 64 + entries
        executable = output / 'Aetheria.exe'
        executable.write_bytes(b'fake-executable' + package + struct.pack('<Q', len(package)) + b'GDPC')
        metadata = {'schema': 1, 'release_id': 'beta-2', 'executable': 'Aetheria.exe',
            'client_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
            'client_bytes': executable.stat().st_size}
        beta_ops.write_json(output / 'release.json', metadata)
        evidence = output.parent / 'beta-2-validation'
        evidence.mkdir()
        beta_ops.write_json(evidence / 'audit.json', {'resources': 2, 'raw_scripts': 0, 'server_resources': 0})
        for name in ('import.log', 'export.log', 'boot.log', 'boot-console.log'):
            (evidence / name).write_text('Godot validation completed')
        with patch.object(server_ops.subprocess, 'run', side_effect=self.export_server):
            executable = server_ops.build('fake-godot', data=self.data)
        # Restore the pre-existing active selection. Reusing must not select it.
        (self.data / 'server-build.json').write_bytes(self.original['server-build.json'])
        legacy = self.data / 'legacy-build.json'
        beta_ops.write_json(legacy, {'schema': 1, 'exe': str(executable), 'repo': str(server_ops.REPO)})
        boot_patch = patch.object(beta_release.subprocess, 'run', side_effect=self.boot_client)
        boot_patch.start()
        self.addCleanup(boot_patch.stop)
        return output, legacy

    def boot_client(self, command, **kwargs):
        self.assertEqual(command[0], str(self.data / 'beta-builds/beta-2/Aetheria.exe'))
        self.assertIn('--headless', command)
        self.assertIn('--quit-after', command)
        self.assertIn('--social-no-auto', command)
        return subprocess.CompletedProcess(command, 0, stdout='Godot startup completed', stderr='')

    def test_reuse_rejects_nonzero_boot_with_clean_old_logs_before_seal_publish_or_activate(self):
        output, legacy = self.reuse_fixture()
        server = Path(beta_ops.read_json(legacy)['exe'])
        receipt = output.parent / 'beta-2-validation/release-candidate.json'
        for schema in (1, 2):
            manifest = legacy if schema == 1 else server_ops.candidate_manifest(server, 'beta-2')
            with self.subTest(server_schema=schema), patch.object(beta_release, 'DATA', self.data), \
                    patch.object(beta_release.subprocess, 'run', return_value=subprocess.CompletedProcess(
                        [], 3221225477, stdout='Godot startup', stderr='')), \
                    patch.object(beta_release, 'publish') as publish, \
                    patch.object(beta_release, 'activate') as activate, \
                    patch.object(sys, 'argv', ['beta_release.py', '--release', 'beta-2',
                        '--reuse-server-build', str(manifest), '--publish', '--activate']):
                with self.assertRaisesRegex(RuntimeError, 'boot'):
                    beta_release.main()
                publish.assert_not_called()
                activate.assert_not_called()
                self.assertFalse(receipt.exists())
                self.assert_old_selection()

    def test_reuse_rejects_fresh_boot_errors_and_client_changes_before_sealing(self):
        output, legacy = self.reuse_fixture()
        receipt = output.parent / 'beta-2-validation/release-candidate.json'
        for stdout, stderr in [('SCRIPT ERROR: startup failed', ''), ('', 'ERROR: runtime failed')]:
            with self.subTest(stdout=stdout, stderr=stderr), patch.object(beta_release, 'DATA', self.data), \
                    patch.object(beta_release.subprocess, 'run', return_value=subprocess.CompletedProcess(
                        [], 0, stdout=stdout, stderr=stderr)):
                with self.assertRaisesRegex(RuntimeError, 'boot'):
                    beta_release.reuse_release(output, 'beta-2', legacy)
                self.assertFalse(receipt.exists())
        executable = output / 'Aetheria.exe'
        def changed_client(command, **kwargs):
            executable.write_bytes(executable.read_bytes() + b'changed')
            return subprocess.CompletedProcess(command, 0, stdout='startup completed', stderr='')
        with patch.object(beta_release, 'DATA', self.data), \
                patch.object(beta_release.subprocess, 'run', side_effect=changed_client):
            with self.assertRaises(RuntimeError):
                beta_release.reuse_release(output, 'beta-2', legacy)
        self.assertFalse(receipt.exists())
        self.assert_old_selection()

    def test_reuse_validated_pair_without_export_or_active_pointer_change(self):
        output, legacy = self.reuse_fixture()
        original_client = (output / 'Aetheria.exe').read_bytes()
        with patch.object(beta_release, 'DATA', self.data), \
                patch.object(beta_release.beta_package, 'build', side_effect=AssertionError('unexpected export')):
            metadata, candidate = beta_release.reuse_release(output, 'beta-2', legacy)
        self.assertEqual(metadata['release_id'], 'beta-2')
        self.assertEqual((output / 'Aetheria.exe').read_bytes(), original_client)
        self.assertEqual((output.parent / 'beta-2-validation/reuse-boot-console.log').read_text(), 'Godot startup completed')
        self.assertEqual(server_ops.verify_candidate(candidate, 'beta-2')['release_id'], 'beta-2')
        self.assert_old_selection()

    def test_reuse_rejects_wrong_release_client_hash_and_failed_boot_evidence(self):
        output, legacy = self.reuse_fixture()
        original = beta_ops.read_json(output / 'release.json')
        for changes in ({'release_id': 'beta-3'}, {'client_sha256': 'f' * 64}, {'client_bytes': 1},
                        {'executable': '../other.exe'}, {'schema': 2}):
            beta_ops.write_json(output / 'release.json', dict(original, **changes))
            with patch.object(beta_release, 'DATA', self.data):
                with self.assertRaises((ValueError, RuntimeError)):
                    beta_release.reuse_release(output, 'beta-2', legacy)
        beta_ops.write_json(output / 'release.json', original)
        (output.parent / 'beta-2-validation/boot-console.log').write_text('SCRIPT ERROR: failed')
        with patch.object(beta_release, 'DATA', self.data):
            with self.assertRaises(RuntimeError):
                beta_release.reuse_release(output, 'beta-2', legacy)
        self.assert_old_selection()

    def test_reuse_cli_republishes_then_activates_exact_existing_pair(self):
        output, legacy = self.reuse_fixture()
        events = []
        def publish(settings, published, release):
            self.assertEqual(published, output)
            self.assertEqual(release, 'beta-2')
            self.assert_old_selection()
            events.append('published')
        def activate(settings, metadata, candidate):
            self.assertEqual(events, ['published'])
            self.assertEqual(metadata['release_id'], 'beta-2')
            self.assertEqual(server_ops.verify_candidate(candidate, 'beta-2')['release_id'], 'beta-2')
            events.append('activated')
        with patch.object(beta_release, 'DATA', self.data), \
                patch.object(beta_release, 'publish', side_effect=publish), \
                patch.object(beta_release, 'activate', side_effect=activate), \
                patch.object(beta_release.beta_package, 'build', side_effect=AssertionError('unexpected export')), \
                patch.object(sys, 'argv', ['beta_release.py', '--release', 'beta-2',
                    '--reuse-server-build', str(legacy), '--publish', '--activate']):
            beta_release.main()
        self.assertEqual(events, ['published', 'activated'])
        self.assert_old_selection()



    def test_upload_processing_timeout_preserves_old_selection(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.run_release('--publish', publish_error=subprocess.TimeoutExpired('butler', 600))
        self.assert_old_selection()

    def test_client_metadata_mismatch_rejected_before_stopping_world(self):
        candidate = self.candidate()
        metadata = self.client_pair(candidate)
        for changes in ({'release_id': '../bad'}, {'client_sha256': 'f' * 64}, {'client_bytes': 0},
                        {'executable': '../other.exe'}):
            with patch.object(beta_release, 'DATA', self.data), patch.object(beta_ops, 'stop') as stop:
                with self.assertRaises((ValueError, RuntimeError)):
                    beta_release.activate(self.settings, dict(metadata, **changes), candidate)
                stop.assert_not_called()
        self.assert_old_selection()

    def test_sealed_pair_refuses_a_different_server_for_the_same_release(self):
        output, legacy = self.reuse_fixture()
        with patch.object(beta_release, 'DATA', self.data):
            beta_release.reuse_release(output, 'beta-2', legacy)
        other = self.candidate()
        with patch.object(beta_release, 'DATA', self.data):
            with self.assertRaises(RuntimeError):
                beta_release.reuse_release(output, 'beta-2', other)
        self.assert_old_selection()

    def test_legacy_reuse_rejects_export_errors_and_bad_pinned_runtime(self):
        output, legacy = self.reuse_fixture()
        server = Path(beta_ops.read_json(legacy)['exe'])
        export_log = server.parent / 'export.log'
        export_log.write_text('ERROR: failed export')
        with patch.object(beta_release, 'DATA', self.data):
            with self.assertRaises(RuntimeError):
                beta_release.reuse_release(output, 'beta-2', legacy)
        export_log.write_text('exported')
        beta_ops.write_json(self.data / 'server-runtime.json', {'schema': 1, 'version': '4.7.2',
            'exe': str(server), 'sha256': 'f' * 64})
        with patch.object(beta_release, 'DATA', self.data):
            with self.assertRaises(RuntimeError):
                beta_release.reuse_release(output, 'beta-2', legacy)
        self.assert_old_selection()

    def test_recovery_bundle_includes_the_previous_server_selection(self):
        import zipfile
        beta_ops.write_json(self.data / 'config.json', {'database': 'postgresql'})
        (self.data / 'server.key').write_text('test-only-private-key')
        def dump(config, target, data):
            target.write_bytes(b'test-only-database')
        with patch.object(server_ops, 'dump_database', side_effect=dump):
            bundle = server_ops.backup(self.data)
        with zipfile.ZipFile(bundle) as archive:
            self.assertEqual(archive.read('server-build.json'), self.original['server-build.json'])
            self.assertEqual(archive.read('world.json'), self.original['world.json'])
            self.assertEqual(archive.read('beta.json'), self.original['beta.json'])


if __name__ == '__main__':
    unittest.main()
