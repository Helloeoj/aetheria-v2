"""Roadmap persistence, failure handling, content and actual Tk integration checks."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import tkinter as tk
import unittest
from unittest.mock import patch

from sentinel_roadmap import RoadmapStore, LOOPS, TASKS, CORE, DEPTH, LOOP_TASKS, BUILD
from sentinel import SentinelApp
from sentinel_monitor import Monitor


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sentinel-roadmap-')
        self.path = Path(self.temp.name) / 'companion/roadmap-progress.json'

    def tearDown(self):
        self.temp.cleanup()

    def test_fresh_board_has_no_claimed_completions(self):
        store = RoadmapStore(self.path)
        self.assertEqual(store.count(), (0, 18))
        self.assertFalse(self.path.exists())

    def test_check_uncheck_and_view_survive_reopening(self):
        store = RoadmapStore(self.path)
        store.set_done('food', True)
        store.set_done('persistence', True)
        store.set_view('mechanics', 'mastery')
        reopened = RoadmapStore(self.path)
        self.assertEqual(reopened.count(), (2, 18))
        self.assertEqual(reopened.state['view'], 'mechanics')
        self.assertEqual(reopened.state['loop'], 'mastery')
        reopened.set_done('food', False)
        self.assertFalse(RoadmapStore(self.path).done('food'))
        self.assertTrue(RoadmapStore(self.path).done('persistence'))

    def test_unknown_future_completion_is_retained_but_not_counted(self):
        self.path.parent.mkdir()
        self.path.write_text(json.dumps({'version': 1, 'completed': {'future-task': '2026-10-19T12:00:00Z'}}))
        store = RoadmapStore(self.path)
        store.set_done('food', True)
        self.assertEqual(store.count(), (1, 18))
        self.assertIn('future-task', RoadmapStore(self.path).state['completed'])

    def test_corrupt_or_unsupported_file_is_never_overwritten(self):
        self.path.parent.mkdir()
        for original in ['{broken', '[]', '{"version":2,"completed":{}}', '{"version":1,"completed":{"food":true}}']:
            self.path.write_text(original)
            store = RoadmapStore(self.path)
            self.assertTrue(store.error)
            with self.assertRaises(OSError):
                store.set_done('food', True)
            self.assertEqual(self.path.read_text(), original)

    def test_write_failure_keeps_last_saved_state(self):
        store = RoadmapStore(self.path)
        store.set_done('food', True)
        original = self.path.read_bytes()
        with patch('sentinel_roadmap.adc.atomic', side_effect=PermissionError('Read only')):
            with self.assertRaises(OSError):
                store.set_done('food', False)
        self.assertTrue(store.done('food'))
        self.assertEqual(self.path.read_bytes(), original)

    def test_content_and_shared_task_references(self):
        self.assertEqual(len(LOOPS), 6)
        self.assertEqual(len(CORE), 8)
        self.assertEqual(len(DEPTH), 6)
        for loop in LOOPS.values():
            self.assertEqual(len(loop['steps']), 6)
            for key in ['name', 'priority', 'question', 'exists', 'gap', 'minimum']:
                self.assertTrue(loop[key])
        referenced = set(key for keys in LOOP_TASKS.values() for key in keys)
        referenced.update(key for _, _, keys in BUILD for key in keys)
        self.assertTrue(referenced <= TASKS.keys())
        self.assertEqual(len(TASKS), len(set(TASKS)))


class PanelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sentinel-roadmap-ui-')
        self.root = Path(self.temp.name)
        self.window = tk.Tk()
        self.errors = []
        self.window.report_callback_exception = lambda *args: self.errors.append(str(args))
        self.app = SentinelApp(self.window, Monitor(self.root, discover=False), start=False)
        self.panel = self.app.roadmap
        self.app.tabs.select(self.panel)
        self.window.update()

    def tearDown(self):
        self.app.close()
        self.temp.cleanup()

    def descendants(self, widget):
        for child in widget.winfo_children():
            yield child
            yield from self.descendants(child)

    def test_tab_and_all_loop_selections(self):
        self.assertIn('Roadmap', [self.app.tabs.tab(tab, 'text') for tab in self.app.tabs.tabs()])
        self.assertEqual([self.panel.views.tab(tab, 'text') for tab in self.panel.views.tabs()], ['Missing loops', 'Core mechanics', 'Build next'])
        for key, data in LOOPS.items():
            self.panel.loop_buttons[key].invoke()
            self.window.update()
            texts = [str(widget.cget('text')) for widget in self.descendants(self.panel.loop_body) if isinstance(widget, tk.Label)]
            self.assertIn(data['question'], texts)
            self.assertIn(data['minimum'], texts)
        self.assertFalse(self.errors)

    def test_checkbox_sync_and_actual_app_reopen(self):
        self.panel.variables['food'].set(True)
        self.panel.toggle('food')
        self.window.update()
        self.assertIn('1 / 18', self.panel.progress_label.cget('text'))
        boxes = [box for box in self.panel.checkboxes if str(box.cget('variable')) == str(self.panel.variables['food'])]
        self.assertGreaterEqual(len(boxes), 3)
        self.assertTrue(all(box.instate(['selected']) for box in boxes))
        self.panel.views.select(1)
        self.panel.select_loop('discovery')
        self.window.update()
        self.app.close()
        self.window = tk.Tk()
        self.app = SentinelApp(self.window, Monitor(self.root, discover=False), start=False)
        self.panel = self.app.roadmap
        self.window.update()
        self.assertTrue(self.panel.variables['food'].get())
        self.assertEqual(self.panel.views.index(self.panel.views.select()), 1)
        self.assertEqual(self.panel.loop_key, 'discovery')

    def test_ui_rolls_back_unsaved_checkbox(self):
        self.panel.variables['food'].set(True)
        with patch('sentinel_roadmap.adc.atomic', side_effect=PermissionError('Read only')):
            self.panel.toggle('food')
        self.assertFalse(self.panel.variables['food'].get())
        self.assertIn('Not saved', self.panel.status.get())
        self.assertIn('0 / 18', self.panel.progress_label.cget('text'))

    def test_minimum_size_scroll_and_monitor_tabs(self):
        self.window.geometry('920x560')
        for i, page in enumerate(self.panel.pages):
            self.panel.views.select(i)
            self.window.update()
            self.assertGreater(page.canvas.winfo_height(), 80)
            self.assertLessEqual(page.body.winfo_width(), page.canvas.winfo_width())
            page.canvas.yview_moveto(1)
            self.window.update()
            self.assertAlmostEqual(page.canvas.yview()[1], 1, places=2)
        self.app.tabs.select(0)
        self.window.update()
        self.assertTrue(self.app.game_card.winfo_ismapped())
        self.app.tabs.select(self.panel)
        self.window.update()
        self.assertFalse(self.app.game_card.winfo_ismapped())
        self.assertFalse(self.errors)


if __name__ == '__main__':
    unittest.main(verbosity=2)
