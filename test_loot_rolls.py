from loot.loot_tables import roll_loot
from pprint import pprint

def main():
    print("=== LOOT ROLL TESTER ===")
    print("Type the name of a monster to roll loot.")
    print("Type '/simulate MONSTER_NAME N' to simulate N rolls.")
    print("Type 'exit' to quit.\n")

    while True:
        command = input("> ").strip()
        if command.lower() == 'exit':
            break

        if command.lower().startswith("/simulate"):
            parts = command.split()

            try:
                # Validate input length
                if len(parts) < 3:
                    raise ValueError("Not enough arguments. Usage: /simulate MONSTER_NAME NUMBER")

                # Last part should be the number
                count = int(parts[-1])
                # Join all other parts as monster name
                monster_name = " ".join(parts[1:-1])

                print(f"\n🔁 Simulating {count} rolls for '{monster_name}':\n")
                for i in range(count):
                    result = roll_loot(monster_name)
                    print(f"🎲 Roll {i + 1}:")
                    pprint(result, sort_dicts=False)
                    print()

            except ValueError as ve:
                print(f"❌ {ve}\n")
            except Exception as e:
                print(f"❌ An unexpected error occurred: {e}\n")

        else:
            result = roll_loot(command)
            print("\n🎲 Result:")
            pprint(result, sort_dicts=False)
            print()

if __name__ == "__main__":
    main()
