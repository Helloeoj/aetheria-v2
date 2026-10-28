"""Deployment safety tests use disposable data and never publish or restart services."""
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

try:
    import sentinel_deploy
except ModuleNotFoundError:
    sentinel_deploy = None


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(sentinel_deploy, 'Sentinel needs its safe deployment controller')
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.local = Path(self.temporary.name)
        self.data = self.local / 'Aetheria/online'
        self.runtime = self.data / 'beta-runtime'
        self.runtime.mkdir(parents=True)
        self.repo = Path(__file__).resolve().parents[1]
        self.engine = self.local / 'godot.exe'
        self.engine.touch()
        self.settings = {'schema': 1, 'world_id': 'world-1', 'owner_username': 'owner',
            'upload_id': 42, 'account_url': 'https://beta.example',
            'world_host': 'relay.example', 'world_port': 21777}
        for name in ('cloudflared', 'node', 'wrangler', 'worker_config', 'playit', 'playit_secret'):
            path = self.runtime / name
            path.touch()
            self.settings[name] = str(path)
        for name in ('butler/butler.exe', 'itch-publisher-creds', 'world-public.crt', 'world-private.key'):
            path = self.runtime / name
            path.parent.mkdir(exist_ok=True)
            path.write_text('publisher-secret' if name == 'itch-publisher-creds' else 'fixture')
        python = self.data / 'venv/Scripts/python.exe'
        python.parent.mkdir(parents=True)
        python.touch()
        self.write('beta-runtime/hosting.json', self.settings)
        self.write('beta-runtime/client-profile.json', {'schema': 1, 'release_id': 'beta-1',
            'world_id': 'world-1', 'account_url': 'https://beta.example',
            'world_host': 'relay.example', 'world_port': 21777, 'tls_name': 'aetheria-beta'})
        self.write('beta-runtime/launcher.json', {'schema': 1, 'upload_id': 42, 'game_id': 123,
            'account_url': 'https://beta.example', 'oauth_client_id': 'public-id',
            'download_bytes_per_second': 500000, 'executable': 'Aetheria.exe'})
        self.identities = {}
        self.select('beta-1')
        self.environment = patch.dict(os.environ, LOCALAPPDATA=str(self.local))
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.identity = patch.object(sentinel_deploy.beta_ops, 'process_identity',
            side_effect=lambda pid: self.identities.get(pid))
        self.identity.start()
        self.addCleanup(self.identity.stop)
        self.source = patch.object(sentinel_deploy.DeploymentController, '_source',
            return_value={'branch': 'codex/test', 'commit': 'abc123', 'changed_files': 2,
                          'summary': ['M godot_client/project.godot'],
                          'description': 'Saved local project, including uncommitted changes.'})
        self.source.start()
        self.addCleanup(self.source.stop)
        self.controller = sentinel_deploy.DeploymentController(self.repo, self.data)

    def write(self, name, value):
        path = self.data / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding='utf-8')

    def select(self, release):
        server = self.data / 'server-builds' / release / 'AetheriaServer.exe'
        server.parent.mkdir(parents=True, exist_ok=True)
        server.write_bytes(b'server')
        server.with_suffix('.pck').write_bytes(b'package')
        candidate = {'schema': 2, 'repo': str(self.repo), 'exe': str(server.resolve()),
            'release_id': release, 'exe_sha256': hashlib.sha256(b'server').hexdigest(),
            'pck_sha256': hashlib.sha256(b'package').hexdigest()}
        self.write(str(server.parent.relative_to(self.data) / 'server-candidate.json'), candidate)
        client = {'schema': 1, 'release_id': release, 'executable': 'Aetheria.exe',
            'client_sha256': hashlib.sha256(b'client').hexdigest(), 'client_bytes': 6}
        self.write('beta-builds/' + release + '/release.json', client)
        (self.data / 'beta-builds' / release / 'Aetheria.exe').write_bytes(b'client')
        self.write('beta-builds/' + release + '-validation/release-candidate.json',
            {'schema': 1, 'client': client, 'server_candidate': str(server.parent / 'server-candidate.json')})
        self.write('beta.json', dict(client, enabled=True))
        self.write('world.json', {'release_id': release, 'world_id': 'world-1', 'port': 24567})
        self.write('server-build.json', candidate)
        self.write('world-ready.json', {'pid': 123, 'world_id': 'world-1', 'port': 24567})
        self.identities[123] = {'pid': 123, 'exe': str(server), 'created': 1}
        records = {}
        for index, name in enumerate(('gateway', 'tunnel', 'relay'), 200):
            identity = {'pid': index, 'exe': str(self.runtime / name), 'created': 1}
            records[name] = identity
            self.identities[index] = identity
        self.write('beta-processes.json', records)
        self.write('beta-active.json', {'release_id': release})

    def child(self, returncode=0, during=None, output='Built safely.\n'):
        child = Mock()
        child.stdout = io.StringIO(output)
        child.wait.side_effect = lambda: (during() if during else None) or returncode
        return child

    def test_preview_is_read_only_and_contains_only_public_target_fields(self):
        before = {p: p.read_bytes() for p in self.data.rglob('*') if p.is_file()}
        preview = self.controller.preview(self.engine)
        self.assertTrue(preview['eligible'], preview['prerequisites'])
        self.assertEqual(preview['target'], {'account_url': 'https://beta.example',
            'world_host': 'relay.example', 'world_port': 21777, 'world_id': 'world-1'})
        self.assertNotIn('publisher-secret', json.dumps(preview))
        self.assertEqual(before, {p: p.read_bytes() for p in self.data.rglob('*') if p.is_file()})

    def test_plain_build_missing_engine_and_mismatched_launcher_are_blocked(self):
        self.write('beta.json', {'enabled': False})
        with patch.object(sentinel_deploy.subprocess, 'Popen') as launch:
            result = self.controller.update(self.engine, lambda line: None)
        self.assertFalse(result['ok'])
        launch.assert_not_called()
        self.select('beta-1')
        self.engine.unlink()
        self.assertFalse(self.controller.preview(self.engine)['eligible'])
        self.engine.touch()
        self.write('beta-runtime/launcher.json', {'schema': 1, 'upload_id': 99})
        self.assertFalse(self.controller.preview(self.engine)['eligible'])

    def test_status_requires_matching_manifests_ready_world_and_real_process(self):
        self.assertTrue(self.controller.status()['ok'])
        self.write('world.json', {'release_id': 'other', 'world_id': 'world-1'})
        self.assertFalse(self.controller.status()['ok'])
        self.select('beta-1')
        self.identities[123]['exe'] = str(self.engine)
        self.assertFalse(self.controller.status()['ok'])
        self.select('beta-1')
        self.write('world-ready.json', {'pid': 123, 'world_id': 'wrong', 'port': 24567})
        self.assertFalse(self.controller.status()['ok'])

    def test_status_rejects_stale_ready_record_and_tampered_client(self):
        self.identities[123]['created'] = 99_999_999_999_999_999_999
        self.assertFalse(self.controller.status()['ok'])
        self.select('beta-1')
        (self.data / 'beta-builds/beta-1/Aetheria.exe').write_bytes(b'tamper')
        self.assertFalse(self.controller.status()['ok'])

    def test_update_reuses_hidden_pipeline_streams_redacted_log_and_verifies_new_release(self):
        child = self.child(during=lambda: self.select('beta-2'),
            output='token=private-token\npublisher-secret\nBuilt safely.\n')
        lines = []
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=child) as launch:
            result = self.controller.update(self.engine, lines.append)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['release_id'], 'beta-2')
        command = launch.call_args.args[0]
        self.assertEqual(command[-2:], [str(self.repo / 'tools/server.ps1'), 'build'])
        self.assertEqual(launch.call_args.kwargs['env']['GODOT'], str(self.engine))
        self.assertEqual(launch.call_args.kwargs['env']['PYTHONUNBUFFERED'], '1')
        self.assertEqual(launch.call_args.kwargs['creationflags'], sentinel_deploy.HIDDEN)
        transcript = Path(result['log_path']).read_text(encoding='utf-8')
        self.assertIn('Built safely.', transcript)
        self.assertNotIn('publisher-secret', transcript + ''.join(lines))
        self.assertNotIn('private-token', transcript + ''.join(lines))
        self.assertFalse(Path(result['log_path']).is_relative_to(self.repo))
        self.assertFalse(result['status']['updating'])
        self.assertFalse((self.runtime / 'sentinel-update.lock').exists())

    def test_exit_zero_without_new_verified_running_release_is_failure(self):
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=self.child()):
            result = self.controller.update(self.engine, lambda line: None)
        self.assertFalse(result['ok'])
        self.assertEqual(result['returncode'], 0)
        self.assertIn('verif', result['message'].lower())

    def test_nonzero_is_propagated_without_retry_or_killing_any_process(self):
        child = self.child(returncode=7)
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=child) as launch:
            result = self.controller.update(self.engine, lambda line: None)
        self.assertFalse(result['ok'])
        self.assertEqual(result['returncode'], 7)
        self.assertEqual(launch.call_count, 1)
        child.kill.assert_not_called()
        child.terminate.assert_not_called()

    def test_existing_release_and_activation_locks_are_never_deleted(self):
        for name in ('release.lock', 'activation.pending', 'sentinel-update.lock'):
            path = self.runtime / name
            path.write_text('owner')
            with patch.object(sentinel_deploy.subprocess, 'Popen') as launch:
                result = self.controller.update(self.engine, lambda line: None)
            self.assertFalse(result['ok'], name)
            launch.assert_not_called()
            self.assertEqual(path.read_text(), 'owner')
            path.unlink()

    def test_second_controller_cannot_start_while_first_is_updating(self):
        nested = []
        second = sentinel_deploy.DeploymentController(self.repo, self.data)
        def during():
            nested.append(second.update(self.engine, lambda line: None))
            self.select('beta-2')
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=self.child(during=during)) as launch:
            result = self.controller.update(self.engine, lambda line: None)
        self.assertTrue(result['ok'])
        self.assertFalse(nested[0]['ok'])
        self.assertEqual(launch.call_count, 1)

    def test_data_target_must_match_server_powershell_runtime(self):
        with patch.dict(os.environ, LOCALAPPDATA=str(self.local / 'other')):
            with patch.object(sentinel_deploy.subprocess, 'Popen') as launch:
                result = self.controller.update(self.engine, lambda line: None)
        self.assertFalse(result['ok'])
        launch.assert_not_called()

    def test_conflicting_account_runtime_override_blocks_before_launch(self):
        with patch.dict(os.environ, AETHERIA_ACCOUNT_DATA=str(self.local / 'development-accounts')):
            self.assertFalse(self.controller.preview(self.engine)['eligible'])
            with patch.object(sentinel_deploy.subprocess, 'Popen') as launch:
                result = self.controller.update(self.engine, lambda line: None)
            self.assertFalse(result['ok'])
            launch.assert_not_called()
        with patch.dict(os.environ, AETHERIA_ACCOUNT_DATA=str(self.data)):
            self.assertTrue(self.controller.preview(self.engine)['eligible'])

    def test_launch_error_is_logged_safely_and_does_not_leave_own_lock(self):
        lines = []
        with patch.object(sentinel_deploy.subprocess, 'Popen',
                          side_effect=OSError('Launch denied token=private-token publisher-secret')):
            result = self.controller.update(self.engine, lines.append)
        self.assertFalse(result['ok'])
        transcript = Path(result['log_path']).read_text(encoding='utf-8')
        self.assertIn('Launch denied', transcript)
        self.assertNotIn('private-token', transcript + ''.join(lines))
        self.assertNotIn('publisher-secret', transcript + ''.join(lines))
        self.assertFalse((self.runtime / 'sentinel-update.lock').exists())

    def test_changed_release_without_its_ready_process_or_ingress_is_not_success(self):
        def wrong_process():
            self.select('beta-2')
            self.identities[123]['exe'] = str(self.engine)
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=self.child(during=wrong_process)):
            self.assertFalse(self.controller.update(self.engine, lambda line: None)['ok'])
        def missing_ingress():
            self.select('beta-3')
            (self.data / 'beta-processes.json').unlink()
        with patch.object(sentinel_deploy.subprocess, 'Popen', return_value=self.child(during=missing_ingress)):
            self.assertFalse(self.controller.update(self.engine, lambda line: None)['ok'])

    def test_malformed_hosting_never_exposes_private_url_credentials(self):
        self.settings['account_url'] = 'https://username:private-password@beta.example/?token=private-token'
        self.write('beta-runtime/hosting.json', self.settings)
        preview = self.controller.preview(self.engine)
        self.assertFalse(preview['eligible'])
        self.assertEqual(preview['target'], {})
        self.assertNotIn('private-password', json.dumps(preview))


if __name__ == '__main__':
    unittest.main()
