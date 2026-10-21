from aetheria_core.player import Player


def test_get_combat_stats_uses_levels_and_gear():
    player = Player("Tester")
    player.set_level("attack", 10)
    player.set_level("strength", 15)
    player.set_level("defence", 8)

    # Equip a weapon with strong slash bonuses to exercise style selection.
    player.give_and_equip("Bronze Longsword")
    player.attack_style = "slash"

    stats = player.get_combat_stats()

    assert stats["style"] == "slash"
    assert stats["min_damage"] == stats["max_damage"] // 3
    # Accuracy should be a rounded float between 0 and 1.
    assert 0.05 <= stats["accuracy"] <= 0.99
    # Ensure health values reflect the player's level setup.
    assert stats["health"]["max"] == player.max_hp
