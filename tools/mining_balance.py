"""Deterministic renewal-rate Mining model; standard library only, no game writes."""
import argparse
import csv
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / 'tools/mining_balance.json'


def thresholds():
    """Read the live curve constants; Godot roundi on positive XP rounds halves up."""
    source = (ROOT / 'godot_client/scripts/skill_progression.gd').read_text()
    def constant(name):
        return float(re.search(r'const ' + name + r' := ([\d_.]+)', source)[1].replace('_', ''))
    low, high = int(constant('MIN_LEVEL')), int(constant('MAX_LEVEL'))
    cap, rate = constant('MAX_EXPERIENCE'), constant('LEVEL_CURVE_RATE')
    return {level: math.floor(cap * math.expm1(rate * (level-low)) /
                             math.expm1(rate * (high-low)) + 0.5)
            for level in range(low, high+1)}


def validate(config):
    def number(value, low, high, integer=False):
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('Invalid numeric balance parameter')
        if integer and int(value) != value:
            raise ValueError('Expected integer')
    number(config['xp_scale'], 0.001, 1000)
    number(config['retarget_seconds'], 0, 60)
    items = {item['id']: item for item in json.loads((ROOT / 'godot_client/data/items.json').read_text())}
    for group in ('ores', 'tools'):
        if not config[group]:
            raise ValueError('Empty balance group')
        seen = set()
        for row in config[group]:
            key = row['item_id'] if group == 'ores' else row['profile']
            if key in seen:
                raise ValueError('Duplicate definition')
            seen.add(key)
            number(row['required_level'], 1, 100, True)
            if group == 'tools':
                if not isinstance(key, str) or not key or 'item_id' in row:
                    raise ValueError('Tools are hypothetical profiles, not item records')
                number(row['interval'], 0.25, 10)
                continue
            number(key, 1, 2147483647, True)
            if key not in items or key in (242, 256) or items[key].get('boss_material', False):
                raise ValueError('Unknown or restricted ore')
            number(row['xp'], 1, 19450000, True)
            number(row['p0'], 0.000001, 1)
            number(row['p1'], row['p0'], 1)
            number(row['mastery_levels'], 1, 99, True)
            number(row['exponent'], 0.01, 10)
            number(row['respawn'], 0.001, 86400)
    if not any(r['required_level'] == 1 for r in config['ores']) or not any(r['required_level'] == 1 for r in config['tools']):
        raise ValueError('Level 1 needs an ore and a tool profile')


def probability(level, ore):
    if level < ore['required_level']:
        return 0.0
    u = min(1.0, max(0.0, (min(level, 100)-ore['required_level']) / ore['mastery_levels']))
    return ore['p0'] + (ore['p1']-ore['p0']) * u ** ore['exponent']


def combinations(level, config):
    """One uncontested deposit per option; full cooldown, no idealized infinite supply."""
    rows = []
    for ore in config['ores']:
        p = probability(level, ore)
        if not p:
            continue
        for tool in config['tools']:
            if level < tool['required_level']:
                continue
            extraction = tool['interval'] / p
            cycle = extraction + ore['respawn'] + config['retarget_seconds']
            ores = 3600 / cycle
            reward = max(1, math.floor(ore['xp'] * config['xp_scale'] + 0.5))
            rows.append(dict(level=level, item_id=ore['item_id'], tool=tool['profile'],
                             probability=p, ores_per_hour=ores, xp_per_hour=ores*reward,
                             reward=reward, extraction_seconds=extraction,
                             availability_fraction=extraction/cycle))
    return sorted(rows, key=lambda r: (-r['xp_per_hour'], r['item_id'], r['tool']))


def progression(config):
    validate(config)
    xp = thresholds()
    cumulative = 0.0
    rows = []
    for level in range(1, 101):
        best = combinations(level, config)[0]
        needed = xp[level+1]-xp[level] if level < 100 else 0
        hours = needed / best['xp_per_hour']
        rows.append(dict(best, xp_to_next=needed, hours_to_next=hours,
                         hours_to_reach=cumulative))
        cumulative += hours
    return rows


def report(config):
    rows = progression(config)
    names = {i['id']: i['name'] for i in json.loads((ROOT / 'godot_client/data/items.json').read_text())}
    lines = ['# Mining balance report', '',
             f'Expected efficient progression: **{rows[-1]["hours_to_reach"]:.2f} hours** (target 60–70).', '',
             '| Level | Best ore / hypothetical tool | Ores/h | XP/h | Hours to next | Hours to reach |',
             '| --- | --- | ---: | ---: | ---: | ---: |']
    selected = {1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100}
    last = None
    for row in rows:
        route = (row['item_id'], row['tool'])
        if row['level'] in selected or route != last:
            lines.append(f'| {row["level"]} | {names[row["item_id"]]} / {row["tool"]} | {row["ores_per_hour"]:.1f} | {row["xp_per_hour"]:,.0f} | {row["hours_to_next"]:.3f} | {row["hours_to_reach"]:.2f} |')
        last = route
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT)
    parser.add_argument('--csv', action='store_true', help='All 100 level rows on stdout')
    parser.add_argument('--compare-level', type=int, choices=range(1, 101), metavar='1..100', help='All unlocked ore/tool rates as CSV')
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    validate(config)
    if args.csv or args.compare_level:
        rows = combinations(args.compare_level, config) if args.compare_level else progression(config)
        writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    else:
        print(report(config))


if __name__ == '__main__':
    main()
