import copy
import json
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


if __name__ == '__main__':
    unittest.main()
