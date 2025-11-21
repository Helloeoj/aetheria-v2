from unittest import mock

from loot import loot_tables


class DummyMonster:
    def __init__(self, tier):
        self.tier = tier


def test_choose_loot_tier_respects_tier_one():
    assert loot_tables.choose_loot_tier(1) == 1


def test_roll_loot_forces_item_when_roll_hits():
    monster = DummyMonster(tier=2)

    random_sequence = iter([
        0.0,  # random.random() -> ensure item drop instead of gold only
        0.0,  # random.random() in choose_loot_tier -> same tier
    ])

    def fake_random():
        return next(random_sequence)

    randint_values = iter([
        7,   # gold amount between tier 2 range
        10,  # weapon roll (not 1)
        50,  # accessory roll (not 1)
        2,   # stack size for crafting/food
    ])

    def fake_randint(*_args, **_kwargs):
        return next(randint_values)

    with mock.patch("loot.loot_tables.random.random", side_effect=fake_random), \
            mock.patch("loot.loot_tables.random.randint", side_effect=fake_randint):
        result = loot_tables.roll_loot(monster)

    assert result["gold"] == 7
    assert result["item"] is not None
    assert result["quantity"] >= 1
