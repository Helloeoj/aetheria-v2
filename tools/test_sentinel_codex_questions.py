"""Question lifecycle regressions using real local memory and no inference."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from sentinel_assistant import build_task
from sentinel_codex import AssistantController
from sentinel_memory import ProjectMemory


class QuestionServer:
    def __init__(self):
        self.calls, self.replies = [], []
        self.callback = None
        self.start_error = None

    def request(self, method, params=None, timeout=30):
        self.calls.append((method, params))
        if method == 'thread/start':
            return {'thread': {'id': 'question'}}
        if method == 'turn/start':
            if self.start_error:
                raise RuntimeError(self.start_error)
            return {'turn': {'id': 'turn-1', 'status': 'inProgress'}}
        return {}

    def reply(self, identity, result=None, error=None):
        self.replies.append((identity, result, error))

    def close(self):
        pass


class QuestionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / 'project'
        self.project.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        (self.project / 'AGENTS.md').write_text('Preserve project work.', encoding='utf-8')
        self.memory = ProjectMemory(self.project, Path(self.temp.name) / 'memory.sqlite3')
        self.addCleanup(self.memory.close)
        self.server, self.events = QuestionServer(), []
        self.controller = AssistantController(self.memory, server=self.server, callback=self.events.append)
        self.addCleanup(self.controller.close)

    def launch(self):
        return self.controller.launch(build_task(self.memory, 'How does fishing work?', mode='question',
                                                model='catalog-model'), approved=True)

    def event(self, method, **params):
        self.controller.event({'method': method, 'params': {'threadId': 'question', 'turnId': 'turn-1', **params}})

    def test_streamed_answer_is_visible_before_completion_and_final_is_not_duplicated(self):
        job = self.launch()
        self.event('item/agentMessage/delta', itemId='answer', delta='Fishing ')
        self.event('item/agentMessage/delta', itemId='answer', delta='uses timing.')
        self.assertEqual(self.events[-1]['answer'], 'Fishing uses timing.')
        self.assertEqual(job['status'], 'running')
        self.event('item/completed', item={'type': 'agentMessage', 'id': 'answer', 'text': 'Fishing uses timing.'})
        self.event('item/completed', item={'type': 'agentMessage', 'id': 'answer', 'text': 'Fishing uses timing.'})
        self.event('item/agentMessage/delta', itemId='answer', delta='duplicate late delta')
        self.event('turn/completed', turn={'id': 'turn-1', 'status': 'completed'})
        self.assertEqual(job['body']['answer'], 'Fishing uses timing.')
        self.assertEqual(self.memory.history()[0]['body']['answer'], 'Fishing uses timing.')

    def test_streamed_answer_is_bounded_and_foreign_turn_is_ignored(self):
        job = self.launch()
        self.event('item/agentMessage/delta', turnId='foreign', itemId='answer', delta='foreign data')
        self.assertEqual(job['answer'], '')
        self.event('item/agentMessage/delta', itemId='answer', delta='x' * 20000)
        self.assertEqual(len(job['answer']), 16000)
        self.event('item/completed', item={'type': 'agentMessage', 'id': 'answer', 'text': 'First explanation.'})
        self.event('item/agentMessage/delta', itemId='final', delta='Final answer.')
        self.assertEqual(job['answer'], 'First explanation.\nFinal answer.')

    def test_nonretryable_error_finishes_visibly_and_keeps_the_actual_reason(self):
        job = self.launch()
        self.event('error', error={'message': 'Model catalog-model is unavailable.', 'codexErrorInfo': 'badRequest'}, willRetry=False)
        self.assertEqual(job['status'], 'failed')
        self.assertIn('Model catalog-model is unavailable.', self.events[-1]['body']['error'])
        self.assertIn('model', self.events[-1]['body']['error'].lower())
        self.assertFalse(self.memory.history()[0]['verified'])

    def test_retry_error_shows_progress_without_pretending_completion(self):
        job = self.launch()
        self.event('error', error={'message': 'Connection interrupted.'}, willRetry=True)
        self.assertEqual(job['status'], 'running')
        self.assertIn('Connection interrupted.', self.events[-1].get('message', ''))

    def test_empty_completed_question_reports_no_answer_instead_of_blank_success(self):
        job = self.launch()
        self.event('turn/completed', turn={'id': 'turn-1', 'status': 'completed'})
        self.assertEqual(job['status'], 'failed')
        self.assertIn('no answer', self.events[-1]['body']['error'].lower())

    def test_question_cannot_request_escalation_and_unsupported_input_is_visible(self):
        job = self.launch()
        start = next(params for method, params in self.server.calls if method == 'thread/start')
        self.assertEqual(start['sandbox'], 'read-only')
        self.assertEqual(start['approvalPolicy'], 'never')
        self.controller.event({'id': 10, 'method': 'item/tool/requestUserInput',
                               'params': {'threadId': 'question', 'turnId': 'turn-1', 'questions': []}})
        self.assertEqual(job['status'], 'failed')
        self.assertIn('input', self.events[-1]['body']['error'].lower())
        self.assertEqual(self.server.replies[-1][2]['code'], -32601)

    def test_question_never_exposes_a_permission_request_as_a_write_approval(self):
        job = self.launch()
        self.controller.event({'id': 11, 'method': 'item/commandExecution/requestApproval',
                               'params': {'threadId': 'question', 'turnId': 'turn-1', 'command': 'write forbidden'}})
        self.assertTrue(self.server.replies, 'Read-only question did not decline the permission request.')
        self.assertEqual(self.server.replies[-1][1], {'decision': 'decline'})
        self.assertEqual(job['status'], 'failed')
        self.assertFalse(any(event['type'] == 'approval' for event in self.events))

    def test_turn_start_failure_checkpoint_keeps_the_real_error(self):
        self.server.start_error = 'Reasoning effort is unsupported for this model.'
        with self.assertRaises(RuntimeError):
            self.launch()
        self.assertIn('Reasoning effort is unsupported', self.memory.history()[0]['body']['error'])

    def test_usage_interruption_retains_its_reason_in_the_final_receipt(self):
        job = self.launch()
        self.event('thread/tokenUsage/updated', tokenUsage={'total': {'totalTokens': 13000}})
        self.event('turn/completed', turn={'id': 'turn-1', 'status': 'interrupted'})
        self.assertEqual(job['status'], 'interrupted')
        self.assertIn('Token budget reached', self.events[-1]['body']['error'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
