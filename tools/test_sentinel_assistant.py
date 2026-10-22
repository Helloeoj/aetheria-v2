"""Assistant regressions; temporary repositories/state, no inference or real credentials."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import time
from unittest.mock import patch

from sentinel_memory import ProjectMemory
from sentinel_assistant import build_task, choose_model, Governor, prepare_attachments
from sentinel_codex import AppServer, AssistantController


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.write('.gitignore', 'ignored/\n.env\n')
        self.write('godot_client/scripts/fishing.gd',
                   'extends Node\n\nfunc catch_chance(skill):\n    return skill * 0.1\n')
        self.write('godot_client/scenes/Lake.tscn',
                   '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/fishing.gd" id="1"]\n')
        self.db = Path(self.temp.name) / 'memory.sqlite3'
        self.memory = ProjectMemory(self.root, self.db)
        self.addCleanup(self.memory.close)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')

    def test_incremental_refresh_reuses_unchanged_source_and_finds_symbols(self):
        first = self.memory.refresh()
        self.assertEqual(first['read'], 2)
        self.assertEqual(self.memory.refresh()['read'], 0)
        results = self.memory.search('catch chance fishing')
        self.assertEqual(results[0]['path'], 'godot_client/scripts/fishing.gd')
        self.assertIn('catch_chance', results[0]['text'])
        self.assertEqual(results[0]['line'], 1)
        self.assertIn('res://scripts/fishing.gd', self.memory.context('Lake'))

    def test_changed_and_deleted_source_never_leaks_stale_snippets(self):
        self.memory.refresh()
        self.write('godot_client/scripts/fishing.gd', 'func fishing_new():\n    return 7\n')
        self.assertNotIn('catch_chance', self.memory.context('fishing'))
        self.memory.refresh()
        self.assertIn('fishing_new', self.memory.context('fishing'))
        (self.root / 'godot_client/scripts/fishing.gd').unlink()
        self.memory.refresh()
        self.assertNotIn('fishing_new', self.memory.context('fishing_new'))
        self.assertNotIn('godot_client/scripts/fishing.gd', [r['path'] for r in self.memory.search('fishing_new')])

    def test_gameplay_answers_prioritize_implementation_over_smoke_tests(self):
        self.write('godot_client/scripts/dev_tools/fishing_smoke.gd',
                   'func test_fishing_catch_chance():\n    # fishing catch chance\n    assert(true)\n')
        self.memory.refresh()
        rows = self.memory.search('How does fishing calculate catch chance?')
        self.assertEqual(rows[0]['path'], 'godot_client/scripts/fishing.gd')

    def test_secret_ignored_binary_and_external_files_are_excluded(self):
        self.write('.env', 'SECRET=do-not-index')
        self.write('ignored/private.py', 'secret_ignored = True')
        self.write('tools/credentials.json', '{"access_token":"secret_token"}')
        self.write('tools/auth.py', 'access_token = "sk-test-secret-012345678901234567890123"\n')
        self.write('art_sources/large.json', '{"asset":"unneeded"}')
        self.memory.refresh()
        self.assertFalse(self.memory.search('secret'))
        self.assertFalse(self.memory.search('unneeded'))
        self.assertLessEqual(len(self.memory.context('fishing', max_chars=180)), 180)

    def test_proposal_approval_supersession_and_rollback_survive_restart(self):
        one = self.memory.propose_rule('fishing', 'Fishing is manual.')
        self.assertEqual(self.memory.rules(), [])
        self.memory.approve_rule(one)
        two = self.memory.propose_rule('fishing', 'Fishing uses stamina.')
        self.memory.approve_rule(two)
        self.assertEqual([r['text'] for r in self.memory.rules()], ['Fishing uses stamina.'])
        self.memory.rollback_rule(one)
        self.assertEqual([r['text'] for r in self.memory.rules()], ['Fishing is manual.'])
        self.assertEqual(len(self.memory.rule_history()), 3)
        with ProjectMemory(self.root, self.db) as reopened:
            self.assertEqual(reopened.rules()[0]['text'], 'Fishing is manual.')

    def test_verification_requires_real_command_and_matching_source(self):
        self.memory.refresh()
        receipt = self.memory.validate([sys.executable, '-c', 'print("checks passed")'], timeout=10)
        key = self.memory.checkpoint('Fishing task', 'completed', {'validation': receipt})
        self.assertTrue(self.memory.history()[0]['verified'])
        self.write('godot_client/scripts/fishing.gd', 'func changed(): pass\n')
        self.assertFalse(self.memory.history()[0]['verified'])
        self.assertEqual(self.memory.history()[0]['id'], key)
        self.memory.checkpoint('Agent says passed', 'completed', {'summary': 'All tests passed'})
        self.assertFalse(self.memory.history()[0]['verified'])

    def test_failed_validation_is_unverified_and_output_is_bounded(self):
        self.memory.refresh()
        receipt = self.memory.validate([sys.executable, '-c', 'print("x"*20000);raise SystemExit(3)'], timeout=10)
        self.assertEqual(receipt['exit_code'], 3)
        self.assertLessEqual(len(receipt['output']), 8000)
        self.memory.checkpoint('Failure', 'completed', {'validation': receipt})
        self.assertFalse(self.memory.history()[0]['verified'])

    def test_database_cannot_be_reused_for_another_project(self):
        other = Path(self.temp.name) / 'other'
        other.mkdir()
        with self.assertRaises(ValueError):
            ProjectMemory(other, self.db)

    def test_attachments_deduplicate_and_require_current_secret_free_content(self):
        first = self.root / 'one.txt'
        second = self.root / 'two.txt'
        first.write_text('Only this selected excerpt.', encoding='utf-8')
        second.write_bytes(first.read_bytes())
        files = prepare_attachments([first, second])
        self.assertEqual(len(files), 1)
        task = build_task(self.memory, 'Explain fishing', mode='question', model='available', attachments=files)
        self.assertIn('Only this selected excerpt.', task['prompt'])
        first.write_text('Changed evidence.', encoding='utf-8')
        controller = AssistantController(self.memory, server=FakeServer())
        self.addCleanup(controller.close)
        with self.assertRaises(ValueError): controller.launch(task, approved=True)
        second.write_text('api_key = "sk-test-secret-012345678901234567890123"', encoding='utf-8')
        with self.assertRaises(ValueError): prepare_attachments([second])

    def test_forged_validation_receipt_does_not_verify_a_task(self):
        self.memory.checkpoint('Forged', 'completed', {'validation': {'id':'invented','exit_code':0}})
        self.assertFalse(self.memory.history()[0]['verified'])

    def test_checkpoint_redacts_credentials_before_serializing_json(self):
        self.memory.checkpoint('Attempt', 'failed', {'answer':'password="abcdefghijklmnop"'})
        self.assertNotIn('abcdefghijklmnop',self.memory.history()[0]['body']['answer'])

    def test_preferences_survive_restart_without_overwriting_corrupt_state(self):
        self.memory.save_preferences({'tokens':8000,'seconds':300})
        with ProjectMemory(self.root,self.db) as reopened:
            self.assertEqual(reopened.preferences(),{'tokens':8000,'seconds':300})

    def test_symbol_beyond_first_chunk_is_retrieved_with_its_line_number(self):
        self.write('godot_client/scripts/large.gd','\n'.join(['# padding']*80+['func rare_catch_formula():','    return 42']))
        self.memory.refresh()
        row=self.memory.search('rare_catch_formula')[0]
        self.assertEqual(row['path'],'godot_client/scripts/large.gd')
        self.assertEqual(row['line'],73)

    def test_corrupt_database_is_preserved(self):
        path=Path(self.temp.name)/'broken.sqlite3'
        path.write_bytes(b'not a database')
        with self.assertRaises(Exception): ProjectMemory(self.root,path)
        self.assertEqual(path.read_bytes(),b'not a database')

    def test_timed_out_validation_cannot_leave_a_child_process_running(self):
        marker=Path(self.temp.name)/'orphan.txt'
        child='import time;from pathlib import Path;time.sleep(2);Path('+repr(str(marker))+').write_text("orphan")'
        parent='import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'+repr(child)+']);time.sleep(60)'
        result=self.memory.validate([sys.executable,'-c',parent],timeout=1)
        self.assertTrue(result['timed_out'])
        time.sleep(1.5)
        self.assertFalse(marker.exists())

    def test_task_is_bounded_uses_approved_intent_and_rejects_stale_preview(self):
        self.memory.refresh()
        proposal = self.memory.propose_rule('fishing', 'Use manual catch timing.')
        task = build_task(self.memory, 'Fix fishing catch chance', mode='implement', tokens=4000, seconds=60)
        self.assertNotIn('Use manual catch timing.', task['prompt'])
        self.memory.approve_rule(proposal)
        task = build_task(self.memory, 'Fix fishing catch chance', mode='implement', tokens=4000, seconds=60)
        self.assertIn('Use manual catch timing.', task['prompt'])
        self.assertIn('catch_chance', task['prompt'])
        self.assertLessEqual(len(task['prompt']), 18000)
        self.assertEqual(task['mode'], 'implement')
        controller = AssistantController(self.memory, server=FakeServer())
        self.addCleanup(controller.close)
        with self.assertRaises(ValueError):
            controller.launch(task, approved=False)
        self.write('godot_client/scripts/fishing.gd', 'func changed(): pass\n')
        with self.assertRaises(ValueError):
            controller.launch(task, approved=True)

    def test_task_reuses_relevant_unfinished_checkpoints_without_calling_them_verified(self):
        self.memory.checkpoint('Fix fishing timing','interrupted',{'answer':'Timing UI updated; input validation remains unfinished.','report':{'tokens':1500}})
        task=build_task(self.memory,'Finish fishing timing',mode='implement')
        self.assertIn('input validation remains unfinished',task['prompt'])
        self.assertIn('unverified',task['prompt'].lower())

    def test_broad_request_starts_with_audit_and_no_automatic_next_stage(self):
        task = build_task(self.memory, 'Migrate the entire game to server authoritative multiplayer', mode='implement')
        self.assertEqual(task['mode'], 'audit')
        self.assertIn('Do not modify', task['prompt'])
        self.assertIn('approval', task['prompt'])


class FakeServer:
    def __init__(self):
        self.calls = []
        self.callback = lambda _: None
        self.count = 0
    def request(self, method, params=None, timeout=30):
        self.calls.append((method, params))
        if method == 'thread/start':
            self.count += 1
            return {'thread': {'id': 'thread-' + str(self.count)}}
        if method == 'turn/start':
            return {'turn': {'id': 'turn-' + str(self.count), 'status': 'inProgress'}}
        return {}
    def close(self): pass


class GovernorTests(unittest.TestCase):
    def test_installed_protocol_agent_spawn_is_interrupted_at_start(self):
        governor=Governor(tokens=1000,seconds=60)
        reason=governor.observe({'method':'item/started','params':{'item':{'type':'collabAgentToolCall','id':'spawn','tool':'spawnAgent'}}})
        self.assertEqual(reason,'Unexpected additional agent activity')

    def test_cumulative_usage_duplicate_events_and_interrupt_once(self):
        governor = Governor(tokens=100, seconds=60, now=0)
        event = {'method': 'thread/tokenUsage/updated', 'params': {'tokenUsage': {'total': {'totalTokens': 75, 'inputTokens': 50, 'cachedInputTokens': 20, 'outputTokens': 25}}}}
        governor.observe(event)
        governor.observe(event)
        self.assertEqual(governor.report()['tokens'], 75)
        event['params']['tokenUsage']['total']['totalTokens'] = 101
        self.assertEqual(governor.observe(event), 'Token budget reached')
        self.assertIsNone(governor.observe(event))
        self.assertEqual(governor.report()['interrupts'], 1)

    def test_timeout_and_scope_are_observed_without_inventing_token_counts(self):
        governor = Governor(tokens=100, seconds=5, scope=['tools/a.py'], now=0)
        governor.observe({'method':'item/completed','params':{'item':{'id':'1','type':'fileChange','changes':[{'path':'godot_client/scripts/b.py'}]}}})
        self.assertIn('scope', ' '.join(governor.report()['warnings']).lower())
        self.assertIsNone(governor.report()['tokens'])
        self.assertEqual(governor.tick(6), 'Time budget reached')
        self.assertIsNone(governor.tick(7))

    def test_repeated_reads_and_failed_tests_reset_after_code_changes(self):
        governor = Governor(tokens=1000, seconds=60, now=0)
        for i in range(3):
            governor.observe({'method':'item/completed','params':{'item':{'id':str(i),'type':'commandExecution','command':'Get-Content tools/a.py','exitCode':0,'commandActions':[{'type':'read','path':'tools/a.py'}]}}}, revision='a')
        self.assertIn('unchanged', ' '.join(governor.report()['warnings']))
        for i in range(3, 6):
            governor.observe({'method':'item/completed','params':{'item':{'id':str(i),'type':'commandExecution','command':'python tools/test_x.py','exitCode':1}}}, revision='b')
        self.assertIn('failed', ' '.join(governor.report()['warnings']))
        self.assertEqual(governor.report()['commands'], 6)

    def test_model_routing_uses_only_catalog_and_supported_effort(self):
        models = [{'id':'small','model':'gpt-6-luna','supportedReasoningEfforts':[{'reasoningEffort':'low'}]},
                  {'id':'large','model':'gpt-6.1-sol','supportedReasoningEfforts':[{'reasoningEffort':'medium'}]}]
        self.assertEqual(choose_model(models, 'Fix a typo'), ('gpt-6-luna', 'low'))
        self.assertEqual(choose_model(models, 'Redesign server authority'), ('gpt-6.1-sol', 'medium'))
        with self.assertRaises(ValueError): choose_model([], 'Fix a typo')

    def test_efficiency_advisor_requires_three_measured_successful_validations(self):
        models=[{'id':'large','model':'gpt-6.1-sol','supportedReasoningEfforts':[{'reasoningEffort':'medium'}]},
                {'id':'small','model':'gpt-6-luna','supportedReasoningEfforts':[{'reasoningEffort':'medium'}]}]
        history=[{'request':'Fix server validation','validation_passed':True,'body':{'model':'gpt-6-luna','report':{'tokens':2000}}} for _ in range(3)]
        self.assertEqual(choose_model(models,'Fix server validation',history=history)[0],'gpt-6-luna')
        history[0]['validation_passed']=False
        self.assertEqual(choose_model(models,'Fix server validation',history=history)[0],'gpt-6.1-sol')


class ControllerTests(unittest.TestCase):
    setUp = MemoryTests.setUp
    write = MemoryTests.write

    def test_transport_loss_marks_owned_job_unfinished_without_waiting_for_budget(self):
        import threading
        server=FakeServer()
        server.closed=threading.Event()
        controller=AssistantController(self.memory,server=server)
        self.addCleanup(controller.close)
        job=controller.launch(build_task(self.memory,'Explain fishing',mode='question',model='available'),approved=True)
        server.closed.set()
        deadline=time.monotonic()+2
        while not job['finished'] and time.monotonic()<deadline: time.sleep(.02)
        self.assertEqual(job['status'],'disconnected')
        self.assertFalse(self.memory.history()[0]['verified'])

    def test_actual_stdio_job_lifecycle_records_usage_and_completion(self):
        script=Path(self.temp.name)/'fake-codex.py'
        script.write_text('''import json,sys
def send(value): print(json.dumps(value),flush=True)
for line in sys.stdin:
 m=json.loads(line); method=m.get('method'); p=m.get('params',{})
 if 'id' not in m: continue
 result={}
 if method=='thread/start': result={'thread':{'id':'owned'}}
 if method=='turn/start':
  if p.get('threadId')!='owned' or not p.get('input'): raise SystemExit(2)
  result={'turn':{'id':'turn-1','status':'inProgress'}}
 send({'id':m['id'],'result':result})
 if method=='turn/start':
  send({'method':'thread/tokenUsage/updated','params':{'threadId':'owned','turnId':'turn-1','tokenUsage':{'total':{'totalTokens':600}}}})
  send({'method':'item/completed','params':{'threadId':'owned','turnId':'turn-1','item':{'type':'agentMessage','id':'answer','text':'Fishing uses catch_chance.'}}})
  send({'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'turn-1','status':'completed'}}})
''')
        server=AppServer(command=[sys.executable,str(script)])
        controller=AssistantController(self.memory,server=server)
        self.addCleanup(controller.close)
        job=controller.launch(build_task(self.memory,'Explain fishing',mode='question',model='available'),approved=True)
        deadline=time.monotonic()+5
        while not job['finished'] and time.monotonic()<deadline: time.sleep(.02)
        self.assertEqual(job['status'],'completed')
        row=self.memory.history()[0]
        self.assertEqual(row['body']['report']['tokens'],600)
        self.assertIn('catch_chance',row['body']['answer'])
        self.assertFalse(row['verified'])
    def test_validation_updates_same_checkpoint_without_double_counting_usage(self):
        controller=AssistantController(self.memory,server=FakeServer())
        self.addCleanup(controller.close)
        task=build_task(self.memory,'Test fishing',model='available',validation=[sys.executable,'-c','print("passed")'])
        job=controller.launch(task,approved=True)
        self.assertEqual(self.memory.history()[0]['status'],'running')
        controller.event({'method':'turn/completed','params':{'threadId':job['thread'],'turn':{'id':job['turn'],'status':'completed'}}})
        controller.validate(job['thread'])
        self.assertEqual(len(self.memory.history()),1)
        self.assertTrue(self.memory.history()[0]['verified'])

    def test_budget_interrupt_is_owned_and_foreign_events_are_ignored(self):
        server = FakeServer()
        controller = AssistantController(self.memory, server=server)
        self.addCleanup(controller.close)
        job = controller.launch(build_task(self.memory, 'Explain fishing',mode='question',model='available',tokens=1000),approved=True)
        event = {'method':'thread/tokenUsage/updated','params':{'threadId':'unrelated','tokenUsage':{'total':{'totalTokens':1200}}}}
        controller.event(event)
        self.assertEqual(job['status'],'running')
        event['params']['threadId'] = job['thread']
        controller.event(event)
        controller.event(event)
        self.assertEqual(job['status'],'stopping')
        self.assertEqual(sum(m=='turn/interrupt' for m,_ in server.calls),1)

    def test_rule_change_invalidates_prepared_task(self):
        controller=AssistantController(self.memory,server=FakeServer())
        self.addCleanup(controller.close)
        task=build_task(self.memory,'Explain fishing',model='available')
        identity=self.memory.propose_rule('fishing','Manual fishing only.')
        self.memory.approve_rule(identity)
        with self.assertRaises(ValueError): controller.launch(task,approved=True)

    def test_completed_owned_task_persists_report_but_agent_claim_is_unverified(self):
        server = FakeServer()
        controller = AssistantController(self.memory, server=server)
        self.addCleanup(controller.close)
        task = build_task(self.memory, 'Explain fishing', mode='question', model='available')
        job = controller.launch(task, approved=True)
        controller.event({'method':'item/completed','params':{'threadId':job['thread'],'turnId':job['turn'],'item':{'id':'a','type':'agentMessage','text':'All tests passed'}}})
        controller.event({'method':'turn/completed','params':{'threadId':job['thread'],'turn':{'id':job['turn'],'status':'completed'}}})
        history = self.memory.history()
        self.assertEqual(history[0]['status'], 'completed')
        self.assertFalse(history[0]['verified'])
        self.assertIn('All tests passed', history[0]['body']['answer'])
        self.assertEqual(sum(method == 'turn/start' for method, _ in server.calls), 1)

    def test_peer_review_requires_approval_and_new_evidence_and_is_readonly(self):
        server = FakeServer()
        controller = AssistantController(self.memory, server=server)
        self.addCleanup(controller.close)
        task = build_task(self.memory, 'Fix fishing', model='available')
        controller.launch(task, approved=True)
        with self.assertRaises(ValueError): controller.review(approved=False)
        review = controller.review(approved=True)
        self.assertEqual(review['task']['mode'], 'review')
        self.assertLessEqual(review['task']['tokens'], 24000)
        reason=review['governor'].observe({'method':'thread/tokenUsage/updated','params':{'tokenUsage':{'total':{'totalTokens':14496}}}})
        self.assertIsNone(reason,'A read-only review must fit the observed Codex startup context.')
        self.assertEqual([p['sandbox'] for m,p in server.calls if m=='thread/start'][-1], 'read-only')
        with self.assertRaises(ValueError): controller.review(approved=True)
        controller.close()
        self.assertEqual(sum(m=='turn/interrupt' for m,_ in server.calls), 2)


class TransportTests(unittest.TestCase):
    def test_stdio_handshake_request_errors_and_server_requests(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / 'server.py'
            script.write_text('''import json,sys
for line in sys.stdin:
    m=json.loads(line)
    if 'id' not in m: continue
    if m.get('method')=='bad':
        print(json.dumps({'id':m['id'],'error':{'code':-1,'message':'bad request'}}),flush=True)
    else:
        print(json.dumps({'id':m['id'],'result':{'ok':True}}),flush=True)
''')
            with AppServer(command=[sys.executable, str(script)]) as server:
                self.assertEqual(server.request('hello'), {'ok': True})
                with self.assertRaises(RuntimeError): server.request('bad')


class PanelTests(unittest.TestCase):
    def test_local_preview_rule_history_and_existing_tabs_at_minimum_window(self):
        import tkinter as tk
        from sentinel import SentinelApp
        from sentinel_monitor import Monitor
        with tempfile.TemporaryDirectory() as folder:
            window = tk.Tk()
            app = SentinelApp(window, Monitor(Path(folder), discover=False), start=False)
            try:
                tabs = [app.tabs.tab(tab, 'text') for tab in app.tabs.tabs()]
                self.assertIn('Development assistant', tabs)
                for label in ['Companion','Incidents','Live log','Explain & chat','Roadmap']:
                    self.assertIn(label, tabs)
                panel = app.development
                app.tabs.select(panel)
                window.geometry('920x560')
                panel.request_box.insert('1.0', 'How does fishing work?')
                panel.mode.set('question')
                panel.prepare()
                deadline = time.monotonic() + 15
                while panel.task is None and time.monotonic() < deadline:
                    window.update()
                    time.sleep(.02)
                self.assertIsNotNone(panel.task)
                self.assertEqual(panel.task['mode'], 'question')
                self.assertIn('Observed source:', panel.preview.get('1.0', 'end'))
                self.assertFalse(panel.run_button.instate(['!disabled']))
                self.assertFalse(app.game_card.winfo_ismapped())
                self.assertGreater(panel.preview.winfo_height(), 40)
                # A queued evidence update can arrive after preparation completed.
                panel.attachments=[{'path':'changed-evidence.txt','kind':'text','hash':'new','text':'changed'}]
                panel.run_task()
                self.assertIn('Evidence changed',panel.status.get())
            finally:
                app.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
