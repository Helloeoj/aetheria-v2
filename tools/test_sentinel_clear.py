"""Regression checks for persistent manual clearing without losing ADC evidence."""
import tempfile
from pathlib import Path
import tkinter as tk
import unittest
from unittest.mock import patch

import adc
from sentinel import SentinelApp
from sentinel_monitor import Monitor


class ClearResultsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sentinel-clear-')
        self.root = Path(self.temp.name)
        self.engine_patch = patch('sentinel_monitor.installed_engine', return_value=None)
        self.engine_patch.start()
        self.model = Monitor(self.root, discover=False)
        self.model._initial_prepared = True
        self.window = None

    def tearDown(self):
        if self.window is not None:
            self.app.close()
        self.model.close()
        self.engine_patch.stop()
        self.temp.cleanup()

    def incident(self, identity='ADC-old', count=2, seen='2026-10-20T10:00:00Z'):
        data = {'id': identity, 'session_id': 'fixture', 'message': 'Error loading a game resource',
                'severity': 'ERROR', 'system': 'Resources', 'count': count, 'first_seen': seen, 'last_seen': seen,
                'fingerprint': identity, 'source': {}, 'backtrace': [], 'context': {}}
        path = self.root / 'sessions/fixture/incidents' / (identity + '.json')
        adc.atomic(path, data)
        return path

    def observed(self):
        return [{'id': row['data']['id'], 'occurrence_count': row['data']['count'],
                 'last_seen': row['data']['last_seen']} for row in self.model.snapshot()['incidents']]

    def clear(self):
        self.model.enqueue('clear', self.observed())
        self.model.step()

    def ui(self):
        self.window = tk.Tk()
        self.window.withdraw()
        self.app = SentinelApp(self.window, self.model, start=False)
        self.app.apply(self.model.snapshot())
        self.window.update_idletasks()
        return self.app

    def test_clear_zeros_count_preserves_reports_and_does_not_claim_a_fix(self):
        path = self.incident()
        original = path.read_bytes()
        self.model._read_incidents()
        self.assertEqual(self.model.snapshot()['open_count'], 1)
        self.clear()
        snapshot = self.model.snapshot()
        self.assertEqual(snapshot['open_count'], 0)
        self.assertTrue(snapshot['incidents'][0]['cleared'])
        self.assertFalse(snapshot['incidents'][0]['resolved'])
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse((self.root / 'resolutions').exists())

    def test_clear_survives_monitor_restart(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        restarted = Monitor(self.root, discover=False)
        restarted._read_incidents()
        self.assertEqual(restarted.snapshot()['open_count'], 0)
        self.assertTrue(restarted.snapshot()['incidents'][0]['cleared'])
        restarted.close()

    def test_repeated_occurrence_reappears_even_in_same_second(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        self.incident(count=3)
        self.model._read_incidents()
        self.assertEqual(self.model.snapshot()['open_count'], 1)
        self.assertFalse(self.model.snapshot()['incidents'][0]['cleared'])

    def test_new_report_after_clear_appears(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        self.incident('ADC-new')
        self.model._read_incidents()
        self.assertEqual(self.model.snapshot()['open_count'], 1)

    def test_new_timestamp_with_same_count_reappears(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        self.incident(seen='2026-10-20T11:00:00Z')
        self.model._read_incidents()
        self.assertEqual(self.model.snapshot()['open_count'], 1)

    def test_reports_arriving_between_click_and_processing_are_not_cleared(self):
        self.incident()
        self.model._read_incidents()
        self.model.enqueue('clear', self.observed())
        self.incident(count=3)
        self.incident('ADC-arrived-after-click')
        self.model.step()
        self.assertEqual(self.model.snapshot()['open_count'], 2)

    def test_save_failure_leaves_results_visible_and_reports_failure(self):
        self.incident()
        self.model._read_incidents()
        atomic = adc.atomic

        def fail_clear(path, value):
            if Path(path) == self.model.cleared_path:
                raise OSError('synthetic write failure')
            return atomic(path, value)

        with patch('sentinel_monitor.adc.atomic', side_effect=fail_clear):
            self.clear()
        self.assertEqual(self.model.snapshot()['open_count'], 1)
        self.assertFalse(self.model.snapshot()['incidents'][0]['cleared'])
        self.assertIn('Could not clear results', self.model.snapshot()['notice'])

    def test_clear_leaves_verified_resolution_receipt_unchanged(self):
        self.incident()
        receipt = self.root / 'resolutions/ADC-old.json'
        adc.atomic(receipt, {'occurrence_count': 2, 'validation': {'exit_code': 0}})
        original = receipt.read_bytes()
        self.model._read_incidents()
        self.clear()
        self.assertEqual(receipt.read_bytes(), original)
        self.assertTrue(self.model.snapshot()['incidents'][0]['resolved'])

    def test_button_resets_list_counter_and_selected_details(self):
        self.incident()
        self.model._read_incidents()
        app = self.ui()
        self.assertEqual(app.filter.get(), 'Unresolved')
        self.assertTrue(app.selected)
        app.clear_button.invoke()
        self.model.step()
        app.apply(self.model.snapshot())
        self.assertEqual(str(app.incident_card.cget('text')), '0')
        self.assertEqual(app.incidents.get_children(), ())
        self.assertIsNone(app.selected)
        self.assertIn('0 results', app.detail.get('1.0', 'end'))
        self.assertTrue(app.clear_button.instate(['disabled']))

    def test_history_remains_available_with_cleared_label(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        app = self.ui()
        app.filter.set('All retained')
        app._show_incidents(force=True)
        self.assertIn('ADC-old', app.incidents.get_children())
        self.assertIn('Cleared', app.incidents.item('ADC-old', 'values')[-1])
        app.copy_selected()
        self.assertIn('Error loading a game resource', self.window.clipboard_get())

    def test_latest_and_companion_do_not_keep_showing_cleared_reports(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        app = self.ui()
        self.assertEqual(app.greeting.cget('text'), 'Standing by.')
        app.copy_latest()
        self.assertEqual(self.window.clipboard_get(), 'No ADC incidents recorded.')
        app.filter.set('All retained')
        app._show_incidents(force=True)
        app.explain_latest()
        self.assertIsNone(app.ai_panel.current_report)

    def test_reopened_ui_keeps_zero_results(self):
        self.incident()
        self.model._read_incidents()
        self.clear()
        app = self.ui()
        self.assertEqual(app.incidents.get_children(), ())
        self.assertEqual(str(app.incident_card.cget('text')), '0')

    def test_clear_control_fits_the_minimum_window(self):
        self.incident()
        self.model._read_incidents()
        app = self.ui()
        self.window.geometry('920x560')
        app.tabs.select(1)
        self.window.update_idletasks()
        toolbar = app.clear_button.master
        self.assertLessEqual(toolbar.winfo_reqwidth(), 920 - 48 - 28)


if __name__ == '__main__':
    unittest.main()
