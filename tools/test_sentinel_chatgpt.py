"""No real account calls: isolated OAuth, DPAPI, identity, streaming and UI regressions."""
from __future__ import annotations
import argparse
import base64
import hashlib
import io
import json
import subprocess
import sys
from pathlib import Path
import tempfile
import threading
import time
import tkinter as tk
import urllib.parse
import urllib.request
from unittest.mock import patch
import adc
import sentinel_chatgpt as ai
from sentinel_explanations import incident_title, report_explanation
from sentinel_chat_panel import ChatPanel


def run(output):
    import jwt
    from cryptography.hazmat.primitives.asymmetric import rsa
    output.mkdir(parents=True, exist_ok=True)
    checks = []

    def check(value, name):
        checks.append({'test': name, 'passed': bool(value)})
        print(('PASS ' if value else 'FAIL ') + name, flush=True)

    def rejects(function):
        try:
            function()
        except ai.ChatGPTError:
            return True
        return False

    store = ai.AccountStore(output / 'identity')
    host = store.state['host_id']
    store.save()
    record = dict(issuer=ai.AUTH, subject='test-subject', email='synthetic@example.invalid', client_id='oaiapp_test',
                  access_token='TEST_ACCESS_NEVER_REAL', refresh_token='TEST_REFRESH_NEVER_REAL', id_token='TEST_ID_NEVER_REAL',
                  scopes=ai.SCOPES.split(), expires_at=time.time() + 3600)
    account_key = store.register(record)
    encrypted = store.path.read_bytes()
    check(b'TEST_ACCESS_NEVER_REAL' not in encrypted and b'synthetic@example.invalid' not in encrypted, 'credentials and account metadata are DPAPI protected, not plaintext')
    reopened = ai.AccountStore(store.home)
    check(reopened.state['host_id'] == host and reopened.account()['access_token'] == record['access_token'], 'host identity and protected session survive restart')
    second = dict(record, client_id='oaiapp_second')
    second_key = store.register(second)
    store.select(account_key)
    check(second_key != account_key and len(store.state['accounts']) == 2 and store.account()['client_id'] == 'oaiapp_test', 'same-email registrations stay distinct and selectable')

    attempt = ai.LoginAttempt(store, timeout=2)
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(attempt.authorization_url()).query)
    digest = base64.urlsafe_b64encode(hashlib.sha256(attempt.verifier.encode()).digest()).rstrip(b'=').decode()
    check(query['client_id'] == ['dynamic_agent_client'] and query['agent_name_hint'] == ['Aetheria Sentinel'] and query['ext_agent_host_id'] == [host], 'new registration uses official dynamic entrypoint and stable opaque host')
    check(query['code_challenge'] == [digest] and query['code_challenge_method'] == ['S256'] and len(attempt.state) >= 40, 'fresh high-entropy state/nonce and correct PKCE S256 challenge')
    fields = attempt.exchange_fields({'state': attempt.state, 'client_id': 'oaiapp_issued', 'code': 'SYNTHETIC_CODE'})
    check(fields['client_id'] == 'oaiapp_issued' and fields['redirect_uri'] == attempt.redirect and fields['resource'] == ai.RESOURCE and 'client_secret' not in fields, 'code exchange uses issued client, original callback and PKCE without secret')
    check(rejects(lambda: attempt.exchange_fields({'state': 'wrong', 'client_id': 'oaiapp_issued', 'code': 'x'})), 'mismatched callback state rejected')
    check(rejects(lambda: attempt.exchange_fields({'state': attempt.state, 'code': 'x'})), 'incomplete dynamic registration rejected')
    check(rejects(lambda: attempt.exchange_fields({'state': attempt.state, 'error': 'access_denied'})), 'declined permission cannot proceed to token exchange')
    attempt.server.server_close()
    returning = ai.LoginAttempt(store, store.account())
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(returning.authorization_url()).query)
    check(query['client_id'] == ['oaiapp_test'] and 'agent_name_hint' not in query and query['id_token_hint'] == ['TEST_ID_NEVER_REAL'], 'returning login reuses its own registration and identity hint')
    check(rejects(lambda: returning.exchange_fields({'state': returning.state, 'client_id': 'oaiapp_other', 'code': 'x'})), 'returning login cannot replace registration with a different client')
    returning.server.server_close()

    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    wrong_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    discovery = {'issuer': ai.AUTH, 'jwks_uri': ai.AUTH + '/.well-known/jwks.json'}
    claims = {'iss': ai.AUTH, 'sub': 'validated-test-user', 'aud': 'oaiapp_issued', 'exp': int(time.time()) + 3600, 'iat': int(time.time()), 'nonce': 'expected'}
    token = jwt.encode(claims, private, algorithm='RS256', headers={'kid': 'synthetic-key'})
    provider = lambda _token: private.public_key()
    checked = ai.validate_identity(token, 'oaiapp_issued', 'expected', discovery, provider)
    check(checked['sub'] == 'validated-test-user', 'maintained JWT verifier validates signature, identity and expected claims')
    check(rejects(lambda: ai.validate_identity(token, 'oaiapp_issued', 'expected', discovery, lambda _token: wrong_key.public_key())), 'invalid ID-token signature rejected')
    check(rejects(lambda: ai.validate_identity(token, 'oaiapp_wrong', 'expected', discovery, provider)), 'wrong ID-token audience rejected')
    check(rejects(lambda: ai.validate_identity(token, 'oaiapp_issued', 'wrong', discovery, provider)), 'wrong ID-token nonce rejected')
    expired = jwt.encode(dict(claims, exp=int(time.time()) - 100), private, algorithm='RS256')
    check(rejects(lambda: ai.validate_identity(expired, 'oaiapp_issued', 'expected', discovery, provider)), 'expired ID token rejected')
    wrong_issuer = jwt.encode(dict(claims, iss='https://not-openai.invalid'), private, algorithm='RS256')
    check(rejects(lambda: ai.validate_identity(wrong_issuer, 'oaiapp_issued', 'expected', discovery, provider)), 'wrong ID-token issuer rejected')
    unsigned = jwt.encode(claims, key='', algorithm='none')
    check(rejects(lambda: ai.validate_identity(unsigned, 'oaiapp_issued', 'expected', discovery, provider)), 'unsigned ID token rejected')

    # Real loopback callback and public-client flow, with synthetic token endpoint and verified-identity stand-in.
    fresh_store = ai.AccountStore(output / 'loopback_identity')
    loopback = ai.LoginAttempt(fresh_store, timeout=4)
    def opener(url):
        params = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        callback = params['redirect_uri'][0] + '?' + urllib.parse.urlencode({'state': params['state'][0], 'client_id': 'oaiapp_loopback', 'code': 'TEST_ONLY'})
        def send():
            with urllib.request.urlopen(callback, timeout=3) as response:
                response.read()
        threading.Thread(target=send, daemon=True).start()
        return True
    tokens = {'access_token': 'LOOPBACK_TEST_ACCESS', 'refresh_token': 'LOOPBACK_TEST_REFRESH', 'id_token': 'LOOPBACK_TEST_ID', 'scope': ai.SCOPES, 'expires_in': 3600}
    with patch.object(ai, '_json', side_effect=[tokens, discovery]), patch.object(ai, 'validate_identity', return_value={'sub': 'loopback-user', 'email': 'test@example.invalid'}):
        connected = loopback.run(opener)
    check(connected['client_id'] == 'oaiapp_loopback' and fresh_store.account()['subject'] == 'loopback-user', 'real loopback callback completes a mocked official OAuth exchange and stores selected account')
    cancelled = ai.LoginAttempt(ai.AccountStore(output / 'cancelled'), timeout=1)
    cancelled.cancelled.set()
    opened = []
    check(rejects(lambda: cancelled.run(lambda url: opened.append(url))) and not opened, 'cancelled sign-in does not open browser or accept credentials')

    client = ai.ChatGPTClient(store)
    account = store.account()
    account['scopes'] = ['openid']
    store.save()
    with patch.object(ai, '_json') as network:
        denied = rejects(client.access)
    check(denied and not network.called, 'identity-only consent cannot trigger plan inference or hidden API fallback')
    store.account()['scopes'] = ai.SCOPES.split()
    store.save()
    with patch.object(ai, '_json', return_value={'models': [{'slug': 'available', 'display_name': 'Available', 'visibility': 'list'}, {'slug': 'hidden', 'visibility': 'hide'}]}):
        listed = client.models()
    check(listed == [{'slug': 'available', 'display_name': 'Available'}], 'model picker is populated from signed-in account catalog, hidden entries excluded')
    store.account()['expires_at'] = 0
    store.save()
    renewed = {'access_token': 'NEW_SYNTHETIC_ACCESS', 'refresh_token': 'ROTATED_SYNTHETIC_REFRESH', 'scope': ai.SCOPES, 'expires_in': 3600}
    with patch.object(ai, '_json', return_value=renewed) as network:
        access = client.access()
    check(access == renewed['access_token'] and store.account()['refresh_token'] == renewed['refresh_token'] and network.call_args.args[1]['client_id'] == 'oaiapp_test', 'refresh rotates tokens atomically using the saved issued client')

    parallel_store = ai.AccountStore(output / 'parallel_identity')
    parallel_store.register(dict(record, expires_at=0, scopes=ai.SCOPES.split()))
    counter = output / 'refresh-count.txt'
    counter.write_text('')
    code = '''import sys,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import sentinel_chatgpt as ai
s=ai.AccountStore(Path(sys.argv[2]))
def refresh(*args,**kwargs):
    with open(sys.argv[3], 'a') as f: f.write('refreshed\\n')
    time.sleep(.3)
    return {'access_token':'NEW_TEST','refresh_token':'ROTATED_TEST','expires_in':3600,'scope':ai.SCOPES}
ai._json=refresh
ai.ChatGPTClient(s).access()
'''
    processes = [subprocess.Popen([sys.executable, '-c', code, str(adc.PROJECT / 'tools'), str(parallel_store.home), str(counter)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(2)]
    statuses = [process.wait(timeout=20) for process in processes]
    check(statuses == [0, 0] and counter.read_text().count('refreshed') == 1, 'two local processes serialize refresh and reuse the latest rotating token set')

    def stream(events):
        return io.BytesIO(b''.join(('data: ' + json.dumps(event) + '\n\n').encode() for event in events))
    updates = []
    answer = ai.consume_stream(stream([{'type': 'response.output_text.delta', 'delta': 'Plain '}, {'type': 'response.output_text.delta', 'delta': 'English.'}, {'type': 'response.completed'}]), updates.append)
    check(answer == 'Plain English.' and updates[-1] == answer, 'streamed text is surfaced and accepted only on response.completed')
    check(rejects(lambda: ai.consume_stream(stream([{'type': 'response.output_text.delta', 'delta': 'partial'}]), lambda _text: None)), 'interrupted stream cannot be marked completed')
    check(rejects(lambda: ai.consume_stream(stream([{'type': 'response.incomplete'}]), lambda _text: None)), 'incomplete response rejected')
    check(rejects(lambda: ai.consume_stream(stream([{'type': 'response.output_text.delta', 'delta': 'partial'}, {'type': 'response.failed', 'response': {'error': {'code': 'subscription_sharing_usage_limit_exceeded'}}}]), lambda _text: None)), 'usage-limit failure after streaming is not treated as successful analysis')
    done = [{'type': 'response.output_text.delta', 'delta': 'hello'}, {'type': 'response.completed'}]
    with patch.object(ai, '_http', return_value=stream(done)) as request:
        client.answer('available-model', 'instructions', [{'role': 'user', 'content': 'synthetic report'}], lambda _text: None)
        body = request.call_args.args[1]
    check(body['store'] is False and body['stream'] is True and set(body) == {'model', 'instructions', 'input', 'store', 'stream'}, 'subscription request uses documented endpoint fields without unsupported API defaults')
    with patch.object(ai, '_json', return_value={'revocation_endpoint': ai.AUTH + '/revoke'}), patch.object(ai, '_http', side_effect=ai.ChatGPTError('network unavailable')):
        revoked = client.disconnect()
    check(not revoked and 'access_token' not in store.account() and store.account()['client_id'] == 'oaiapp_test', 'failed remote revocation still clears local secrets while retaining registration')

    incident = dict(schema_version=1, id='ADC-TEST', session_id='session', severity='ERROR', kind='suspected_termination', system='Session',
                    message='Suspected abnormal termination', count=1, first_seen=adc.now(), last_seen=adc.now(), source={}, backtrace=[], context={},
                    recent_events=[], details={}, native_logs=[str(Path.home() / 'private-native.log')], capture='missing marker; not proof', samples=[])
    plain = ai.local_explanation(incident)
    check('does not tell us which' in plain and 'not proof of a cause' in plain and 'game crashed' not in plain.lower(), 'local explanation does not turn missing shutdown marker or breadcrumbs into a proven cause')
    context = ai.evidence_message(incident, str(Path.home() / 'private-report.json'))
    check(str(Path.home()) not in context['content'] and '<user>' in context['content'], 'AI evidence removes local home-directory identity while preserving useful paths')
    inventory = dict(incident, id='ADC-INVENTORY', kind='native_log_import', system='Engine',
                     message="Invalid call. Nonexistent 'String' constructor.",
                     source={'file': 'res://scripts/ui_inventory_menu.gd', 'line': 680, 'function': '_item_bonus_text'})
    explanation = ai.local_explanation(inventory)
    check('Feathers already exist' in explanation and 'no equipment slot' in explanation and 'res://' not in explanation
          and 'constructor' not in explanation and 'doesn\'t identify the item' in explanation,
          'inventory error translates to gameplay meaning without blaming an unrecorded item or exposing code')
    unknown = ai.local_explanation(dict(inventory, source={}, message='Unknown error in res://secret.gd:99'))
    check('res://' not in unknown and 'reliable plain-language explanation' in unknown, 'unknown errors admit the limit without showing raw messages as an explanation')
    pickup = ai.local_explanation(dict(incident, recent_events=[{'action': 'collect ground item', 'data': {'item': 'Feathers'}}]))
    check('Feathers' in pickup and 'Timing alone doesn\'t prove' in pickup, 'last item action is translated as an observation rather than an invented cause')
    receipt = {'incident_id': inventory['id'], 'occurrence_count': 1, 'resolved_at': 'synthetic', 'note': 'Feathers display fixed and pickup checked.', 'validation': {'exit_code': 0}}
    fixed_row = {'data': inventory, 'path': str(output / 'inventory.json'), 'resolved': True, 'resolution': receipt}
    check('Feathers display fixed' in report_explanation(fixed_row)
          and 'A fix has been checked' not in report_explanation(dict(fixed_row, data=dict(inventory, count=2))),
          'checked fix is explained only for the validated occurrence count; recurrence is not treated as fixed')

    window = tk.Tk()
    panel = ChatPanel(window, lambda: {'data': incident, 'path': str(output / 'incident.json')}, store=ai.AccountStore(output / 'ui_identity'))
    panel.pack(fill='both', expand=True)
    try:
        with patch.object(ai, '_http', side_effect=AssertionError('No network allowed')):
            panel.set_report({'data': incident, 'path': str(output / 'incident.json')})
            window.update()
        check('Explained on your computer' in panel.display and not panel.busy, 'UI explains selected incident locally with no network request')
        panel._models([{'slug': 'newer', 'display_name': 'Newer'}, {'slug': 'gpt-5.6-sol', 'display_name': 'GPT-5.6 Sol'}])
        check(panel._model() == 'gpt-5.6-sol', 'requested GPT-5.6 is preferred only when present in the authorized catalog')
        panel._models([{'slug': 'only-authorized', 'display_name': 'Only authorized'}])
        check(panel._model() == 'only-authorized', 'unavailable GPT-5.6 is not fabricated or sent as an unauthorized model')
        panel.cache[(panel.incident_key, 'only-authorized')] = 'Cached synthetic explanation.'
        panel.analyze()
        check('cached' in panel.display and not panel.busy, 'same incident count/model reuses completed cached explanation without inference')
    finally:
        panel.close()
        window.destroy()

    from sentinel import SentinelApp
    from sentinel_monitor import Monitor
    window = tk.Tk()
    app = SentinelApp(window, Monitor(output / 'full-ui', discover=False), start=False)
    try:
        state = app.monitor.snapshot()
        state.update(incidents=[{'data': incident, 'path': str(output / 'incident.json'), 'resolved': False}], open_count=1)
        app.apply(state)
        app.explain_report()
        window.update()
        widgets = [app.ai_panel.analyze_button, app.ai_panel.entry, app.ai_panel.send_button]
        origin_x, origin_y = window.winfo_rootx(), window.winfo_rooty()
        fits = all(widget.winfo_ismapped() and widget.winfo_rootx() - origin_x + widget.winfo_width() <= window.winfo_width()
                   and widget.winfo_rooty() - origin_y + widget.winfo_height() <= window.winfo_height() for widget in widgets)
        check(fits and not app.ai_panel.connect_button.winfo_ismapped()
              and app.ai_panel.conversation_handoff is not None and 'Explained on your computer' in app.ai_panel.display,
              'incident discussion uses embedded ChatGPT routing and its controls fit the real application window')
        state.update(incidents=[fixed_row, state['incidents'][0]], open_count=1)
        app.apply(state)
        app.explain_latest()
        window.update()
        check(app.selected == inventory['id'] and app.ai_panel.current_report['data']['id'] == inventory['id']
              and 'Feathers display fixed' in app.ai_panel.display, 'Explain latest opens the newest report even when an older unresolved report was selected')
        app.tabs.select(1)
        window.update()
        check(inventory['message'] not in app.detail.get('1.0', 'end') and 'res://' not in app.detail.get('1.0', 'end')
              and incident_title(inventory) in app.incidents.item(inventory['id'], 'values')[-1], 'default incident list and details explain the issue without programmer error text')
        app.technical.set(True)
        app.render_detail()
        check(inventory['message'] in app.detail.get('1.0', 'end') and 'ui_inventory_menu.gd' in app.detail.get('1.0', 'end'), 'technical evidence remains available on request')
        app.technical.set(False)
        app.render_detail()
        check('Feathers display fixed' in app.detail.get('1.0', 'end') and app.selected == inventory['id'], 'returning from technical details preserves the selected report and human explanation')
        app.copy_selected()
        check(inventory['message'] in window.clipboard_get(), 'Copy for Codex retains the exact evidence needed to investigate')
        check('Feathers display fixed' in app.ai_panel._evidence()['content'], 'ChatGPT receives the applicable tested fix so it can explain the current state')
        app.ai_panel.set_report(dict(fixed_row, data=dict(inventory, count=2), resolved=False))
        check('Feathers display fixed' not in app.ai_panel._evidence()['content'], 'new occurrence does not pass an obsolete fix to ChatGPT as a current resolution')
        long_row = dict(fixed_row, resolution=dict(receipt, note='Feathers display fixed. ' * 60), signature=('long',))
        state.update(incidents=[long_row], open_count=0)
        app.apply(state)
        app.tabs.select(0)
        window.geometry('920x560')
        window.update()
        check(app.launch_button.winfo_ismapped() and app.launch_button.winfo_rooty() + app.launch_button.winfo_height() <= window.winfo_rooty() + window.winfo_height()
              and app.explanation.winfo_width() <= 920, 'long explanations still leave companion controls accessible at the minimum window size')
    finally:
        app.close()

    failures = [row['test'] for row in checks if not row['passed']]
    adc.atomic(output / 'validation.json', {'completed': adc.now(), 'passed': len(checks) - len(failures), 'failed': failures, 'checks': checks,
                                         'live_account_sign_in_tested': False, 'live_inference_tested': False})
    print(f'ChatGPT integration: {len(checks) - len(failures)}/{len(checks)} checks passed. Live user sign-in is still required.')
    return int(bool(failures))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    raise SystemExit(run(args.output or Path(tempfile.mkdtemp(prefix='sentinel-chatgpt-tests-'))))
