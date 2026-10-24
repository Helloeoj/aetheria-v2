import copy
import json
import subprocess
import sys
import unittest
import mining_balance as sim


class MiningBalanceTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads(sim.DEFAULT.read_text())

    def test_live_curve_milestones(self):
        xp = sim.thresholds()
        self.assertEqual((xp[1], xp[90], xp[100]), (0, 9725000, 19450000))
        self.assertTrue(all(xp[i+1] > xp[i] for i in range(1, 100)))

    def test_geometric_extraction_and_cooldown(self):
        self.config['ores'] = [dict(self.config['ores'][0], p0=0.5, p1=0.5, respawn=4)]
        self.config['tools'] = [dict(self.config['tools'][0], interval=2)]
        self.config['retarget_seconds'] = 1
        row = sim.combinations(1, self.config)[0]
        self.assertEqual(row['extraction_seconds'], 4)
        self.assertEqual(row['ores_per_hour'], 400)

    def test_unlock_mastery_and_high_level(self):
        ore = self.config['ores'][1]
        self.assertEqual(sim.probability(11, ore), 0)
        self.assertEqual(sim.probability(12, ore), ore['p0'])
        self.assertAlmostEqual(sim.probability(42, ore), ore['p1'])
        self.assertEqual(sim.probability(100, dict(ore, required_level=100)), ore['p0'])

    def test_quality_and_level_improve_same_ore(self):
        a = sim.combinations(80, self.config)
        bronze = [r for r in a if r['item_id'] == 235]
        self.assertGreater(bronze[0]['xp_per_hour'], bronze[-1]['xp_per_hour'])
        self.assertGreater(sim.combinations(10, self.config)[0]['xp_per_hour'], sim.combinations(1, self.config)[0]['xp_per_hour'])

    def test_availability_sensitivity(self):
        before = sim.progression(self.config)[-1]['hours_to_reach']
        for ore in self.config['ores']:
            ore['respawn'] *= 2
        self.assertGreater(sim.progression(self.config)[-1]['hours_to_reach'], before)

    def test_deterministic_route_accounting_and_target(self):
        rows = sim.progression(self.config)
        self.assertEqual(rows, sim.progression(self.config))
        self.assertEqual(sum(r['xp_to_next'] for r in rows), sim.thresholds()[100])
        self.assertAlmostEqual(sum(r['hours_to_next'] for r in rows), rows[-1]['hours_to_reach'])
        self.assertTrue(60 <= rows[-1]['hours_to_reach'] <= 70)
        for row in rows:
            self.assertEqual(row['xp_per_hour'], max(r['xp_per_hour'] for r in sim.combinations(row['level'], self.config)))

    def test_invalid_and_restricted_configuration(self):
        for field, value in [('p0', float('nan')), ('respawn', -1), ('item_id', 256), ('required_level', 1.5)]:
            config = copy.deepcopy(self.config)
            config['ores'][0][field] = value
            with self.assertRaises(ValueError):
                sim.validate(config)

    def test_runtime_mapping_preserves_rewards_and_does_not_invent_tools(self):
        runtime = json.loads((sim.ROOT / 'godot_client/data/mining.json').read_text())
        config = sim.normalize_config(runtime, retarget_seconds=1.2)
        self.assertEqual(config['xp_scale'], 1)
        self.assertEqual(config['tools'], [])
        self.assertEqual(config['ores'], [dict(item_id=235, required_level=1, xp=121,
            p0=0.28, p1=0.78, mastery_levels=26, exponent=1.15, respawn=4)])
        with self.assertRaisesRegex(ValueError, 'no pickaxes'):
            sim.progression(config)

    def test_runtime_cli_reports_unavailable_without_traceback_or_estimate(self):
        result = subprocess.run([sys.executable, str(sim.ROOT / 'tools/mining_balance.py'),
            '--config', str(sim.ROOT / 'godot_client/data/mining.json')],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no pickaxes', result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_runtime_requires_explicit_retarget_and_rejects_non_pickaxe(self):
        runtime = json.loads((sim.ROOT / 'godot_client/data/mining.json').read_text())
        # An invalid existing ore ID must never become a substitute pickaxe.
        runtime['pickaxes'] = [dict(item_id=235, required_level=1, attempt_interval_seconds=3)]
        with self.assertRaisesRegex(ValueError, 'retarget'):
            sim.validate(sim.normalize_config(runtime))
        with self.assertRaisesRegex(ValueError, 'catalog pickaxe'):
            sim.validate(sim.normalize_config(runtime, retarget_seconds=1.2))

    def test_runtime_rate_ties_use_numeric_tool_order(self):
        self.config['runtime'] = True
        # Rate-comparison labels only, not catalog items or valid runtime definitions.
        self.config['tools'] = [dict(self.config['tools'][0], profile=label)
                                for label in ('10', '2')]
        self.assertEqual(sim.combinations(1, self.config)[0]['tool'], '2')


if __name__ == '__main__':
    unittest.main()
