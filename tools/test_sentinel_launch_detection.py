"""A background world server must not occupy Sentinel's playable-client slot."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import adc
from sentinel_monitor import Monitor
from sentinel_windows import is_game


# Enumeration fixtures need an existing executable, not a machine-specific
# Godot installation. Command-line classification is exercised independently.
ENGINE = Path(sys.executable)
WORLD_SCENE = 'res://scenes/network/WorldServer.tscn'


def command(*arguments, project=adc.GAME):
    return subprocess.list2cmdline([str(ENGINE), '--path', str(project), *arguments])


class ClientClassificationTests(unittest.TestCase):
    def test_dedicated_world_server_is_not_a_playable_client(self):
        for arguments in [
            ('--headless', WORLD_SCENE, '--', '--world-server', '--social-no-auto'),
            (WORLD_SCENE,),
            ('--headless', '--', '--world-server'),
        ]:
            with self.subTest(arguments=arguments):
                self.assertFalse(is_game(command(*arguments), adc.GAME))

    def test_real_client_and_headless_diagnostic_probe_remain_detectable(self):
        self.assertTrue(is_game(command(), adc.GAME))
        self.assertTrue(is_game(command('--headless', 'res://diagnostics/probe.tscn'), adc.GAME))
        self.assertTrue(is_game(command('--editor-pid', '1234', '--remote-debug',
                                        'tcp://127.0.0.1:6007', '--scene',
                                        'res://scenes/Main.tscn'), adc.GAME))

    def test_other_projects_and_editor_are_not_clients(self):
        self.assertFalse(is_game(command(project=adc.PROJECT / 'other-project'), adc.GAME))
        self.assertFalse(is_game(command('--editor'), adc.GAME))
        self.assertFalse(is_game(command('--project-manager'), adc.GAME))


@unittest.skipUnless(os.name == 'nt', 'Windows process discovery regression')
class MonitorClientDetectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sentinel-client-detection-')
        self.root = Path(self.temp.name)
        self.models = []
        # Supply only the OS enumeration boundary. ProcessWatch still retains a
        # real live process handle; no game, server, or user process is stopped.
        self.pid = os.getpid()

    def tearDown(self):
        for model in self.models:
            model.close()
            for record in model.active.values():
                record['watch'].close()
        self.temp.cleanup()

    def model(self):
        model = Monitor(self.root)
        self.models.append(model)
        return model

    def marker(self, context):
        adc.atomic(self.root / 'sessions/live/session.json', {
            'schema_version': 1, 'session_id': 'live', 'pid': self.pid,
            'started': adc.now(), 'clean_shutdown': False, 'context': context,
        })

    def step(self, model, arguments=None):
        processes = [] if arguments is None else [{
            'ProcessId': self.pid, 'ExecutablePath': str(ENGINE),
            'CommandLine': command(*arguments),
        }]
        with patch('sentinel_monitor.godot_pids', return_value={self.pid} if processes else set()), \
                patch('sentinel_monitor.engine_processes', return_value=processes):
            model.step()

    def test_discovered_server_does_not_block_client_launch(self):
        model = self.model()
        self.step(model, ('--headless', WORLD_SCENE, '--', '--world-server'))
        self.assertEqual(model.snapshot()['active'], [])
        self.assertFalse(any(row['level'] == 'GAME' for row in model.activity))

    def test_server_marker_cannot_bypass_classification_even_on_restart(self):
        for context in ({}, {'scene': WORLD_SCENE}):
            with self.subTest(context=context):
                self.marker(context)
                for _ in range(2):
                    model = self.model()
                    self.step(model, ('--headless', WORLD_SCENE, '--', '--world-server'))
                    self.assertEqual(model.snapshot()['active'], [])
                    self.assertFalse(any(row['level'] == 'GAME' for row in model.activity))

    def test_unrelated_live_pid_in_old_marker_does_not_block_launch(self):
        self.marker({})
        model = self.model()
        self.step(model)
        self.assertEqual(model.snapshot()['active'], [])

    def test_real_client_marker_attaches_and_prevents_duplicate_launch(self):
        self.marker({'scene': 'res://network/login_screen.tscn'})
        model = self.model()
        self.step(model, ())
        self.assertEqual([row['pid'] for row in model.snapshot()['active']], [self.pid])
        self.assertEqual(model.snapshot()['active'][0]['session'], 'live')
        with self.assertRaisesRegex(ValueError, 'already running'):
            model.launch(str(ENGINE))

    def test_marker_seen_before_client_discovery_links_without_a_rewrite(self):
        self.marker({})
        model = self.model()
        self.step(model)
        self.step(model, ())
        self.assertEqual(model.snapshot()['active'][0]['session'], 'live')

    def test_incomplete_process_enumeration_is_retried(self):
        self.marker({})
        model = self.model()
        with patch('sentinel_monitor.godot_pids', return_value={self.pid}), \
                patch('sentinel_monitor.engine_processes', return_value=[]):
            model.step()
        self.step(model, ())
        self.assertEqual([row['pid'] for row in model.snapshot()['active']], [self.pid])
        self.assertEqual(model.snapshot()['active'][0]['session'], 'live')


if __name__ == '__main__':
    unittest.main()
