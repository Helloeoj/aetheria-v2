"""Conservative, offline translations for the owner's main view; raw evidence stays separate."""
import re


def _description(incident):
    source = incident.get('source') or {}
    file = str(source.get('file', '')).replace('\\', '/')
    function = str(source.get('function', ''))
    message = str(incident.get('message', '')).lower()
    area = ('Inventory' if file.endswith('/ui_inventory_menu.gd') else
            {'Resources': 'Game files', 'Session': 'Game session', 'Character': 'Characters'}.get(incident.get('system'), 'Game'))
    if incident.get('kind') == 'suspected_termination':
        return ('The game stopped without saying goodbye', 'Game session',
                "I noticed that Aetheria ended without recording its usual goodbye.\n\n"
                "That can happen when the game is forcibly stopped, closed from the editor, loses power, or crashes. This report does not tell us which happened.\n\n"
                "I can't tell you why it stopped yet. The nearby item and monster actions are not proof of a cause.\n\n"
                "Next: launch Aetheria through Sentinel and tell me what you were doing if it happens again. I will keep the game's last messages so we have more to work with.")
    if file.endswith('/ui_inventory_menu.gd') and function == '_item_bonus_text' and "nonexistent 'string' constructor" in message:
        return ('The inventory had trouble displaying an item', 'Inventory',
                "I found a problem while the inventory was preparing an item's details.\n\n"
                "This matches a problem with items that have no equipment slot. Crafting materials such as Feathers are allowed to have no slot, but the display code did not handle that properly. Feathers already exist in the game; this error does not mean they need to be added.\n\n"
                "This report confirms an inventory display error. It doesn't identify the item on its own or prove that the entire game crashed.\n\n"
                "Next: share this report with your coding assistant to check the inventory display, then test collecting the item and opening its details again.")
    if 'parse error' in message or 'compile error' in message or 'compilation failed' in message:
        return ('Part of the game could not start', area,
                "Aetheria couldn't understand part of its game instructions. That part may not have started or loaded.\n\n"
                "This is a problem in the game's code. It does not mean you did anything wrong while playing.\n\n"
                "Next: use Copy for Codex and share the report with your coding assistant so it can repair and test that part of the game.")
    if any(term in message for term in ('failed loading resource', 'cannot open file', 'error loading', 'resource file not found')):
        return ('The game could not open something it needs', area,
                "Aetheria tried to open a game file and couldn't use it. A missing, moved, or unreadable file is one possibility.\n\n"
                "The report doesn't yet tell us why the file couldn't be used. This could affect loading a level, picture, sound, or another part of the game.\n\n"
                "Next: share the report with your coding assistant so it can check the file and test loading it again.")
    if 'null' in message or 'previously freed' in message:
        return ('The game tried to use something that was unavailable', area,
                "Aetheria expected something to be ready, but it wasn't there when the game tried to use it.\n\n"
                "That could mean something hadn't loaded yet or had already been removed. The report needs investigation before I can say which, or what you would have noticed on screen.\n\n"
                "Next: tell me what you were doing just before this appeared, and share the report with your coding assistant.")
    if 'out of bounds' in message or 'out of range' in message:
        return ('The game looked for an entry that was not there', area,
                "Aetheria tried to choose something from a list, but the place it asked for didn't exist.\n\n"
                "That is a game logic problem. The report doesn't tell us which visible item or action triggered it yet.\n\n"
                "Next: share this report and what you were doing with your coding assistant so it can check the list and test the same action.")
    return ('A problem needs a closer look', area,
            "Aetheria recorded a problem, but I don't yet have a reliable plain-language explanation for this type of error.\n\n"
            "I won't guess that the last item you picked up caused it. The report also doesn't establish whether the whole game closed or one action failed.\n\n"
            "Next: choose Explain with ChatGPT to discuss the evidence, or use Copy for Codex and tell your coding assistant what you were doing. The technical details are saved if they are needed.")


def incident_title(incident):
    return _description(incident)[0]


def incident_area(incident):
    return _description(incident)[1]


def _recent_action(incident):
    # Name an observed item, without turning proximity into a diagnosis.
    for event in reversed((incident.get('recent_events') or [])[-12:]):
        action = event.get('action')
        item = str((event.get('data') or {}).get('item', ''))
        if action not in ('display item details', 'collect ground item', 'spawn ground item') or not item:
            continue
        item = re.sub(r'[\r\n\t]', ' ', item)[:70]
        if '://' in item or '\\' in item or '/' in item:
            continue
        verb = {'display item details': 'showing details for', 'collect ground item': 'attempting to pick up', 'spawn ground item': 'placing a ground drop of'}[action]
        return f"The last recorded item activity was {verb} {item}. Timing alone doesn't prove that caused the problem."
    return ''


def local_explanation(incident):
    if not incident:
        return 'I have no report to explain yet. I will keep watch while you play.'
    text = _description(incident)[2]
    if incident.get('kind') == 'suspected_termination' and (incident.get('details') or {}).get('native_evidence', {}).get('crash_signature_found'):
        text += "\n\nOne saved game log also contains signs of a crash, but I haven't confirmed that it belongs to this stop."
    action = _recent_action(incident)
    if action:
        text += '\n\n' + action
    return text


def verified_resolution(row):
    receipt = row.get('resolution') or {}
    return bool(row.get('resolved') and receipt.get('incident_id') == row['data'].get('id')
                and receipt.get('occurrence_count', 0) >= row['data'].get('count', 1)
                and receipt.get('validation', {}).get('exit_code') == 0)


def report_explanation(row):
    if not row:
        return local_explanation(None)
    if verified_resolution(row):
        return ("A fix has been checked for this report.\n\n" + str(row['resolution'].get('note', 'A passing check was recorded.'))[:2400]
                + "\n\nYou can try the same action again in the updated game. I will keep watching in case it comes back.")
    return local_explanation(row['data'])
