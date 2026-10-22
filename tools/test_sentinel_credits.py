"""Credit-budget behavior with local fakes only; never invokes a model."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from sentinel_assistant import build_task, Governor
from sentinel_codex import AssistantController
from sentinel_memory import ProjectMemory


class CreditServer:
    def __init__(self):
        self.calls = []
        self.usage = None
        self.unsupported = False
        self.balance = '100'

    def request(self, method, params=None, timeout=30):
        self.calls.append((method, params))
        if method == 'thread/start':
            return {'thread': {'id': 'owned'}}
        if method == 'turn/start':
            return {'turn': {'id': 'turn-1', 'status': 'inProgress'}}
        if method == 'account/usage/read':
            if self.unsupported:
                raise RuntimeError('Unknown method account/usage/read')
            return {'summary': {}, 'threadUsage': self.usage}
        if method == 'account/rateLimits/read':
            return {'rateLimits': {'credits': {'balance': self.balance, 'hasCredits': True, 'unlimited': False}},
                    'ordinaryUsageAllowed': False}
        return {}

    def close(self):
        pass


class CreditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.memory = ProjectMemory(self.root, Path(self.temp.name) / 'memory.sqlite3')
        self.addCleanup(self.memory.close)
        self.events, self.server = [], CreditServer()
        self.controller = AssistantController(self.memory, server=self.server, callback=self.events.append)
        self.addCleanup(self.controller.close)

    def task(self, **kwargs):
        return build_task(self.memory, 'Explain this game.', model=kwargs.pop('model', 'gpt-6-luna'),
                          mode='question', **kwargs)

    def test_paid_launch_without_explicit_positive_credit_limit_never_starts_a_turn(self):
        with self.assertRaisesRegex(ValueError, '[Cc]redit'):
            self.controller.launch(self.task(), approved=True)
        self.assertFalse(any(method == 'turn/start' for method, _ in self.server.calls))

    def test_decimal_credit_limit_keeps_exact_microcredits_and_rejects_invalid_limits(self):
        task = self.task(credit_limit='0.000001')
        self.assertEqual(task['credit_limit_micros'], 1)
        for invalid in (0, -1, 'NaN', 'Infinity', True, '0.0000001'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.task(credit_limit=invalid)

    def test_fresh_known_model_awaits_real_usage_without_inventing_zero_spend(self):
        job = self.controller.launch(self.task(credit_limit=2), approved=True)
        report = job['governor'].report()
        self.assertIsNone(report['credits'])
        self.assertEqual(report['credit_source'], 'awaiting_usage')
        self.assertTrue(report['credit_limit_is_soft'])

    def test_unpriced_model_and_missing_server_estimate_block_before_paid_turn(self):
        with self.assertRaisesRegex(ValueError, '[Cc]redit'):
            self.controller.launch(self.task(model='unknown-model', credit_limit=2), approved=True)
        self.assertFalse(any(method == 'turn/start' for method, _ in self.server.calls))

    def test_server_estimate_stops_only_the_owned_job_at_its_credit_threshold(self):
        self.server.usage = {'threadId': 'owned', 'estimatedUsageCreditsMicros': 0, 'groups': []}
        job = self.controller.launch(self.task(model='unknown-model', credit_limit='.25'), approved=True)
        self.server.usage['estimatedUsageCreditsMicros'] = 250000
        self.controller.refresh_job_usage('owned')
        self.assertEqual(job['status'], 'stopping')
        self.assertEqual(job['governor'].report()['credits'], .25)
        self.assertEqual(job['governor'].report()['credit_source'], 'server_estimate')
        self.assertEqual(sum(method == 'turn/interrupt' for method, _ in self.server.calls), 1)

    def test_foreign_thread_estimate_cannot_authorize_an_unpriced_launch(self):
        self.server.usage = {'threadId': 'other', 'estimatedUsageCreditsMicros': 0, 'groups': []}
        with self.assertRaises(ValueError):
            self.controller.launch(self.task(model='unknown-model', credit_limit=2), approved=True)
        self.assertFalse(any(method == 'turn/start' for method, _ in self.server.calls))

    def test_published_rates_use_cached_input_and_output_without_double_counting_reasoning(self):
        job = self.controller.launch(self.task(credit_limit='.003'), approved=True)
        self.controller.event({'method': 'thread/tokenUsage/updated', 'params': {'threadId': 'owned', 'turnId': 'turn-1',
            'tokenUsage': {'total': {'totalTokens': 1100, 'inputTokens': 1000, 'cachedInputTokens': 400,
                                    'outputTokens': 100, 'reasoningOutputTokens': 20}}}})
        report = job['governor'].report()
        self.assertEqual(report['estimated_credits_micros'], 2850)
        self.assertEqual(report['credits'], .00285)
        self.assertEqual(report['credit_source'], 'published_rate_estimate')
        self.assertEqual(job['status'], 'running')
        self.controller.event({'method': 'thread/tokenUsage/updated', 'params': {'threadId': 'owned',
            'tokenUsage': {'total': {'totalTokens': 1200, 'inputTokens': 1000, 'cachedInputTokens': 400, 'outputTokens': 200}}}})
        self.assertEqual(job['status'], 'stopping')

    def test_unknown_token_components_do_not_become_zero_credit_estimates(self):
        job = self.controller.launch(self.task(credit_limit=2), approved=True)
        self.controller.event({'method': 'thread/tokenUsage/updated', 'params': {'threadId': 'owned',
                              'tokenUsage': {'total': {'totalTokens': 10000}}}})
        self.assertIsNone(job['governor'].report()['credits'])

    def test_balance_changes_are_displayed_but_never_attributed_to_the_job(self):
        job = self.controller.launch(self.task(credit_limit=2), approved=True)
        first = self.controller.refresh_account_usage()
        self.server.balance = '90'
        latest = self.controller.refresh_account_usage()
        self.assertEqual(first['balance'], '100')
        self.assertEqual(latest['balance'], '90')
        self.assertIs(latest['ordinary_usage_allowed'], False)
        self.assertIsNone(job['governor'].report()['credits'])
        self.assertEqual(self.events[-1]['type'], 'account_usage')

    def test_unsupported_endpoint_uses_published_rates_without_claiming_server_measurement(self):
        self.server.unsupported = True
        job = self.controller.launch(self.task(credit_limit=2), approved=True)
        self.assertEqual(job['governor'].report()['credit_source'], 'awaiting_usage')
        self.assertIn('unavailable', ' '.join(job['governor'].report()['warnings']).lower())

    def test_server_usage_disappearing_never_turns_missing_data_into_zero(self):
        self.server.usage = {'threadId': 'owned', 'estimatedUsageCreditsMicros': 0, 'groups': []}
        job = self.controller.launch(self.task(credit_limit=2), approved=True)
        self.server.usage = None
        report = self.controller.refresh_job_usage('owned')
        self.assertIsNone(report['credits'])
        self.assertEqual(report['credit_source'], 'awaiting_usage')

    def test_missing_account_values_stay_unavailable_instead_of_zero_or_false(self):
        self.controller.server = CreditServer()
        self.controller.server.request = lambda *args, **kwargs: {'rateLimits': {}}
        usage = self.controller.refresh_account_usage()
        self.assertIsNone(usage['balance'])
        self.assertIsNone(usage['ordinary_usage_allowed'])
        self.assertIsNone(usage['has_credits'])
        self.assertFalse(usage['available'])

    def test_fractional_microcredit_estimate_rounds_up_instead_of_understating_usage(self):
        governor = Governor(model='gpt-6-luna', seconds=60, credit_limit_micros=3)
        governor.observe({'method': 'thread/tokenUsage/updated', 'params': {
            'tokenUsage': {'total': {'totalTokens': 1, 'inputTokens': 1, 'cachedInputTokens': 0, 'outputTokens': 0}}}})
        self.assertEqual(governor.report()['estimated_credits_micros'], 3)
        self.assertEqual(governor.reason, 'Credit budget reached (estimated; reporting may lag)')

    def test_sparse_account_update_preserves_known_permission_and_refreshes_balance(self):
        self.controller.refresh_account_usage()
        self.controller.event({'method': 'account/rateLimits/updated', 'params': {
            'rateLimits': {'credits': {'balance': '75', 'hasCredits': True, 'unlimited': False}}}})
        self.assertEqual(self.events[-1]['usage']['balance'], '75')
        self.assertIs(self.events[-1]['usage']['ordinary_usage_allowed'], False)

    def test_refresh_without_connection_is_unavailable_and_never_contacts_a_model(self):
        self.controller.server = None
        usage = self.controller.refresh_account_usage()
        self.assertFalse(usage['available'])
        self.assertIsNone(usage['balance'])
        self.assertIn('Connect', usage['error'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
