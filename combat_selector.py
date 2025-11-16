from monsters import MONSTER_DATABASE, get_monster
from combat.combat_engine import fight_turn


def print_monster_list():
    print("\n=== MONSTER REGISTRY ===")
    for name in MONSTER_DATABASE:
        print(f"- {name}")
    print("========================\n")


def fight(mon1_name, mon2_name):
    m1 = get_monster(mon1_name)
    m2 = get_monster(mon2_name)

    if m1 is None:
        print(f"❌ Monster not found: {mon1_name}")
        return
    if m2 is None:
        print(f"❌ Monster not found: {mon2_name}")
        return

    # Make fresh copies so HP resets each fight
    import copy
    m1 = copy.deepcopy(m1)
    m2 = copy.deepcopy(m2)

    print(f"\n⚔️  {m1.name} (HP {m1.health})  VS  {m2.name} (HP {m2.health}) ⚔️\n")
    round_num = 1

    while m1.health > 0 and m2.health > 0:
        print(f"--- ROUND {round_num} ---")
        print(fight_turn(m1, m2))
        if m2.health <= 0:
            print(f"\n🏆 {m1.name} WINS!\n")
            return

        print(fight_turn(m2, m1))
        if m1.health <= 0:
            print(f"\n🏆 {m2.name} WINS!\n")
            return

        round_num += 1


def main():
    print("=== AETHERIA COMBAT SELECTOR ===")
    print("Type '/list' to show monsters.")
    print("Use: /fight MonsterA VS MonsterB")
    print("Type 'exit' to quit.\n")

    while True:
        cmd = input("> ")

        if cmd.lower() == "exit":
            break

        if cmd.lower() == "/list":
            print_monster_list()
            continue

        if cmd.lower().startswith("/fight"):
            parts = cmd[6:].strip().split("VS")
            if len(parts) != 2:
                print("❌ Format: /fight MonsterA VS MonsterB")
                continue

            mon1 = parts[0].strip()
            mon2 = parts[1].strip()

            fight(mon1, mon2)
            continue

        print("❌ Unknown command. Use '/list' or '/fight A VS B'.")


if __name__ == "__main__":
    main()
