"""Owned Codex app-server stdio connection and finite, explicitly approved jobs."""
from __future__ import annotations
from collections import deque
import copy
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import threading
import time
from sentinel_memory import HIDDEN, safe_text
from sentinel_assistant import Governor, build_task, rules_signature, prepare_attachments
from sentinel_process import ProcessGroup


def installed_codex():
    executable = shutil.which('codex.exe') or shutil.which('codex')
    if executable:
        return executable
    candidates = list((Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'OpenAI/Codex/bin').glob('*/codex.exe'))
    if not candidates:
        raise FileNotFoundError('Codex was not found. Choose the installed codex.exe in Connect Codex.')
    return str(max(candidates, key=lambda p: p.stat().st_mtime_ns))


class AppServer:
    def __init__(self, executable=None, *, command=None, callback=None):
        self.callback = callback or (lambda _: None)
        self.lock, self.write_lock = threading.Lock(), threading.Lock()
        self.pending, self.sequence = {}, 0
        self.closed = threading.Event()
        self.events = queue.Queue(maxsize=512)
        self.stderr = deque(maxlen=8)
        args = command or [executable or installed_codex(), 'app-server', '--listen', 'stdio://',
                           '-c', 'features.multi_agent=false', '-c', 'web_search="disabled"']
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding='utf-8', errors='replace', bufsize=1, creationflags=HIDDEN,
                                        start_new_session=os.name != 'nt')
        self.group = ProcessGroup(self.process)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.dispatcher = threading.Thread(target=self._dispatch, daemon=True)
        self.reader.start()
        self.dispatcher.start()
        self.stderr_worker = threading.Thread(target=self._stderr, daemon=True)
        self.stderr_worker.start()
        try:
            self.request('initialize', {'clientInfo': {'name': 'aetheria_sentinel', 'title': 'Aetheria Sentinel', 'version': '0.2.0'}}, timeout=20)
            self.notify('initialized', {})
        except Exception:
            self.close()
            raise

    def __enter__(self): return self
    def __exit__(self, *_): self.close()

    def _send(self, value):
        if self.closed.is_set():
            raise RuntimeError('Codex connection is closed. Reconnect before launching another job.')
        with self.write_lock:
            try:
                self.process.stdin.write(json.dumps(value, ensure_ascii=False) + '\n')
                self.process.stdin.flush()
            except (OSError, ValueError):
                raise RuntimeError('Codex connection stopped.') from None

    def request(self, method, params=None, timeout=30):
        with self.lock:
            self.sequence += 1
            identity = self.sequence
            signal = threading.Event()
            entry = {'signal': signal}
            self.pending[identity] = entry
        try:
            self._send({'id': identity, 'method': method, 'params': params or {}})
            if not signal.wait(timeout):
                raise TimeoutError('Codex did not acknowledge ' + method + '. No automatic retry was made.')
            result = entry['reply']
            if 'error' in result:
                raise RuntimeError(safe_text(result['error'].get('message', 'Codex request failed.'))[:500])
            return result.get('result', {})
        finally:
            with self.lock:
                self.pending.pop(identity, None)

    def notify(self, method, params=None):
        self._send({'method': method, 'params': params or {}})

    def reply(self, identity, result=None, error=None):
        self._send({'id': identity, **({'error': error} if error else {'result': result})})

    def _read(self):
        reason = 'Codex app-server disconnected; any unfinished job needs attention.'
        try:
            while not self.closed.is_set():
                line = self.process.stdout.readline(4_000_001)
                if not line:
                    break
                if len(line) > 4_000_000:
                    reason = 'Codex event exceeded the local transport limit.'
                    break
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(value, dict):
                    continue
                if 'id' in value and 'method' not in value:
                    with self.lock:
                        entry = self.pending.get(value['id'])
                        if entry:
                            entry['reply'] = value
                            entry['signal'].set()
                else:
                    try:
                        self.events.put(value, timeout=.2)
                    except queue.Full:
                        if value.get('method', '').endswith('delta') or value.get('method', '').endswith('Delta'):
                            continue
                        reason = 'Codex event queue overflowed; stopped to preserve accurate oversight.'
                        break
        except (OSError, ValueError):
            pass
        finally:
            self.closed.set()
            self.group.close()
            if self.process.poll() is None:
                self.process.terminate()
            with self.lock:
                for entry in self.pending.values():
                    entry['reply'] = {'error': {'message': reason}}
                    entry['signal'].set()
            # Dispatcher drains existing lifecycle messages before the disconnect.
            try:
                self.events.put({'method': 'sentinel/disconnected', 'params': {'message': reason}}, timeout=1)
            except queue.Full:
                pass

    def _stderr(self):
        try:
            for line in self.process.stderr:
                # Do not persist server logs or credentials. Only bounded safe diagnostics.
                self.stderr.append(safe_text(line[:500]))
        except (OSError, ValueError):
            pass

    def _dispatch(self):
        while not self.closed.is_set() or not self.events.empty():
            try:
                event = self.events.get(timeout=.2)
            except queue.Empty:
                continue
            try:
                self.callback(event)
            except Exception:
                # Callback failures must not silently lose the lifecycle of a live job.
                self.closed.set()
                if self.process.poll() is None:
                    self.process.terminate()
                break

    def close(self):
        self.closed.set()
        self.group.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        for worker in (self.reader, self.dispatcher):
            if worker is not threading.current_thread():
                worker.join(timeout=2)
        # A descendant may still own an inherited pipe. Closing a TextIOWrapper
        # while another thread is blocked in readline can hang on its IO lock.
        streams = [self.process.stdin]
        if not self.reader.is_alive(): streams.append(self.process.stdout)
        if not self.stderr_worker.is_alive(): streams.append(self.process.stderr)
        for stream in streams:
            try:
                stream.close()
            except OSError:
                pass


class AssistantController:
    def __init__(self, memory, server=None, callback=None):
        self.memory, self.server = memory, server
        self.callback = callback or (lambda _: None)
        self.lock = threading.RLock()
        self.jobs = {}
        self.closed = threading.Event()
        self.reviews = 0
        self.last_review = None
        self.corrections = set()
        self.approvals = {}
        if server:
            server.callback = self.event
        self.watchdog = threading.Thread(target=self._watch, daemon=True)
        self.watchdog.start()

    def connect(self, executable=None):
        if self.server:
            self.server.close()
        self.server = AppServer(executable, callback=self.event)
        account = self.server.request('account/read', {'refreshToken': False})
        models, cursor = [], None
        for _ in range(10):
            page = self.server.request('model/list', {'limit': 100, 'cursor': cursor, 'includeHidden': False})
            models.extend(page.get('data', []))
            cursor = page.get('nextCursor')
            if not cursor:
                break
        return {'account': account.get('account'), 'models': models}

    def launch(self, task, *, approved=False):
        if not approved:
            raise ValueError('Review the task, model and budget, then approve this stage.')
        if self.closed.is_set() or not self.server:
            raise ValueError('Connect Codex first.')
        if not task.get('model'):
            raise ValueError('Choose a model from the connected catalog.')
        if task['revision'] != self.memory.snapshot() or task['rules'] != rules_signature(self.memory):
            raise ValueError('Project source or approved rules changed. Prepare a fresh preview.')
        if task.get('attachments') and prepare_attachments([a['path'] for a in task['attachments']]) != task['attachments']:
            raise ValueError('Selected evidence changed. Prepare a fresh preview.')
        with self.lock:
            if task['mode'] != 'review' and any(j['status'] in ('running', 'stopping') and j['task']['mode'] != 'review' for j in self.jobs.values()):
                raise ValueError('Finish or stop the current developer job before starting another.')
            thread = self.server.request('thread/start', {
                'cwd': str(self.memory.project), 'model': task['model'],
                'approvalPolicy': 'on-request' if task['mode'] == 'implement' else 'never', 'approvalsReviewer': 'user',
                'sandbox': 'workspace-write' if task['mode'] == 'implement' else 'read-only',
                'serviceName': 'aetheria_sentinel', 'serviceTier': 'default',
                'config': {'features.multi_agent': False, 'web_search': 'disabled'},
                'developerInstructions': ('One approved stage only. No extra agents or automatic follow-on jobs. Follow the task scope and project rules.'
                    + (' Answer the question read-only. Do not edit files, commit, push, or request elevated permissions.'
                       if task['mode'] == 'question' else ''))})['thread']['id']
            job = {'thread': thread, 'turn': None, 'task': copy.deepcopy(task), 'status': 'running',
                   'answer': '', 'messages': {}, 'message': 'Waiting for Codex to answer…',
                   'diff': '', 'governor': Governor(tokens=task['tokens'], seconds=task['seconds'], scope=task['scope']),
                   'checkpoint': None, 'finished':False, 'corrections': 0, 'last_checkpoint':time.monotonic()}
            self.jobs[thread] = job
            try:
                job['turn'] = self.server.request('turn/start', {'threadId': thread,
                    'input': [{'type': 'text', 'text': task['prompt']}] + [
                        {'type':'localImage','path':a['path']} for a in task.get('attachments',[]) if a['kind']=='image'], 'model': task['model'],
                    'effort': task['effort'], 'serviceTier': 'default'})['turn']['id']
                job['checkpoint']=self.memory.checkpoint(task['request'],'running',{'model':task['model'],
                    'effort':task['effort'],'mode':task['mode'],'thread':thread,'turn':job['turn'],
                    'source_revision':task['revision'],'report':job['governor'].report(),
                    'answer':'Stage started; no completion receipt yet.','validation':None})
            except Exception as error:
                self._finish(job, 'failed', 'Codex could not start this request. ' + self._error_message(error))
                self.server.close()
                raise
            self.callback({'type': 'job', 'thread': thread, 'status': 'running'})
            self._progress(job)
            return job

    def event(self, event):
        if self.closed.is_set():
            return
        with self.lock:
            method, params = event.get('method', ''), event.get('params', {})
            if method == 'sentinel/disconnected':
                for job in self.jobs.values():
                    if job['status'] in ('running', 'stopping'):
                        self._finish(job, 'disconnected', params.get('message', 'Connection stopped.'))
                return
            if 'id' in event and 'method' in event:
                job = self.jobs.get(params.get('threadId'))
                matching_turn=job and params.get('turnId')==job.get('turn')
                approval = method in ('item/commandExecution/requestApproval', 'item/fileChange/requestApproval')
                if matching_turn and job['status'] == 'running' and approval and job['task']['mode'] == 'implement':
                    self.approvals[event['id']] = event
                    self.callback({'type':'approval','id':event['id'],'method':method,'params':params})
                else:
                    if approval:
                        self.server.reply(event['id'], {'decision': 'decline'})
                    else:
                        self.server.reply(event['id'], error={'code': -32601, 'message': 'This client does not support this request.'})
                    if matching_turn and job['status'] == 'running':
                        reason = ('This read-only request asked for extra permissions, which Sentinel declined. Ask a narrower question.'
                                  if approval or method == 'item/permissions/requestApproval' else
                                  'Codex requested input that Sentinel cannot display yet. Add the missing detail to your question and ask again.')
                        self.interrupt(job['thread'], reason)
                        self._finish(job, 'failed', reason)
                return
            job = self.jobs.get(params.get('threadId'))
            if not job:
                return
            if job['status'] not in ('running','stopping'):
                if method=='thread/tokenUsage/updated' and job.get('body'):
                    job['governor'].observe(event)
                    job['body']['report']=job['governor'].report()
                    self.memory.update_checkpoint(job['checkpoint'],job['status'],job['body'])
                return
            turn = params.get('turnId') or params.get('turn', {}).get('id')
            if turn and job['turn'] and turn != job['turn']:
                return
            if method == 'error':
                message = self._error_message(params.get('error', {}))
                if not params.get('willRetry', False):
                    self._finish(job, 'failed', message)
                else:
                    job['message'] = message + ' Codex is retrying the connection…'
                    self._progress(job)
                return
            revision = self.memory.snapshot() if method == 'item/completed' else ''
            reason = job['governor'].observe(self._relative_event(event), revision=revision)
            if method == 'turn/diff/updated':
                job['diff'] = safe_text(params.get('diff', ''))[-20000:]
            if method == 'item/agentMessage/delta':
                self._answer(job, params.get('itemId'), params.get('delta', ''), completed=False)
                job['message'] = 'Writing answer…'
            if method == 'item/started':
                kind = params.get('item', {}).get('type')
                if kind == 'commandExecution':
                    job['message'] = 'Reading project files…' if job['task']['mode'] != 'implement' else 'Working on the approved change…'
                elif kind == 'agentMessage':
                    job['message'] = 'Writing answer…'
            if method == 'item/completed' and params.get('item', {}).get('type') == 'agentMessage':
                self._answer(job, params['item'].get('id'), params['item'].get('text', ''), completed=True)
            if reason:
                self.interrupt(job['thread'], reason)
            if method == 'turn/completed':
                error = params['turn'].get('error')
                self._finish(job, params['turn'].get('status', 'failed'), self._error_message(error) if error else '')
            else:
                if job['checkpoint'] and time.monotonic()-job['last_checkpoint']>=1:
                    self.memory.update_checkpoint(job['checkpoint'],job['status'],{
                        'model':job['task']['model'],'effort':job['task']['effort'],'mode':job['task']['mode'],
                        'thread':job['thread'],'turn':job['turn'],'report':job['governor'].report(),
                        'answer':job['answer'],'validation':None})
                    job['last_checkpoint']=time.monotonic()
                self._progress(job)

    def _progress(self, job):
        self.callback({'type': 'progress', 'thread': job['thread'], 'report': job['governor'].report(),
                       'answer': job['answer'], 'message': job['message']})

    def _answer(self, job, identity, text, *, completed):
        # Final items contain the whole message, not another delta. Retain only a
        # bounded tail and replace that item's draft to avoid duplicated answers.
        identity = identity or 'answer'
        previous = job['messages'].get(identity, {'text': '', 'completed': False})
        if previous['completed'] and not completed:
            return
        job['messages'][identity] = {'text': safe_text(text if completed else previous['text'] + text)[-16000:],
                                     'completed': completed}
        while len(job['messages']) > 32:
            del job['messages'][next(iter(job['messages']))]
        job['answer'] = safe_text('\n'.join(row['text'] for row in job['messages'].values() if row['text']))[-16000:]

    @staticmethod
    def _error_message(error):
        message = safe_text(error.get('message', 'Codex could not complete this request.') if isinstance(error, dict) else str(error))[:800]
        detail = (message + ' ' + str(error.get('codexErrorInfo', '') if isinstance(error, dict) else '')).lower()
        if any(word in detail for word in ('unauthorized', 'sign in', 'authentication', 'token expired')):
            action = 'Sign in to Codex again, then reconnect.'
        elif any(word in detail for word in ('usagelimit', 'ratelimit', 'usage limit', 'rate limit', 'quota')):
            action = 'Check your Codex usage limits before trying again.'
        elif any(word in detail for word in ('model', 'effort', 'badrequest')):
            action = 'Reconnect to refresh the model list, or choose another available model in Advanced controls.'
        else:
            action = 'Check the Codex connection and try again; no new request was started automatically.'
        return message + ' ' + action

    def _relative_event(self, event):
        result = copy.deepcopy(event)
        for change in result.get('params', {}).get('item', {}).get('changes', []):
            path = Path(change.get('path', ''))
            if path.is_absolute():
                try: change['path'] = path.relative_to(self.memory.project).as_posix()
                except ValueError: pass
        return result

    def _finish(self, job, status, error=''):
        if job.get('finished'):
            return
        if status == 'completed' and job['task']['mode'] == 'question' and not job['answer'].strip():
            status, error = 'failed', 'Codex returned no answer. Try a more specific question or reconnect Codex.'
        if status != 'completed' and not error:
            error = job['governor'].reason or 'Codex stopped before completing the request. Try again or reconnect Codex.'
        job['finished']=True
        job['status'] = status
        body = {'model':job['task']['model'], 'effort':job['task']['effort'], 'mode':job['task']['mode'],
                'answer':job['answer'], 'error':error, 'report':job['governor'].report(),
                'source_revision':job['task']['revision'], 'rules_revision':job['task']['rules'],
                'thread':job['thread'], 'turn':job['turn'], 'validation':None}
        if job['checkpoint']:
            self.memory.update_checkpoint(job['checkpoint'],status,body)
        else:
            job['checkpoint'] = self.memory.checkpoint(job['task']['request'], status, body)
        job['body'] = body
        self.callback({'type':'finished','thread':job['thread'],'status':status,'body':body})

    def validate(self, thread):
        with self.lock:
            job = self.jobs[thread]
            if job['status'] != 'completed' or not job['task']['validation']:
                raise ValueError('Validation requires a completed task and a reviewed validation command.')
            argv = list(job['task']['validation'])
        receipt = self.memory.validate(argv, timeout=min(120, job['task']['seconds']),cancel=self.closed)
        with self.lock:
            body = dict(job['body'], validation=receipt)
            self.memory.update_checkpoint(job['checkpoint'],job['status'],body)
            job['body'] = body
            return receipt

    def interrupt(self, thread, reason='Stopped by owner'):
        with self.lock:
            job = self.jobs[thread]
            if job['status'] != 'running':
                return
            job['status'] = 'stopping'
            job['stopping_at'] = time.monotonic()
            job['governor'].stop(reason)
            if job['turn']:
                try:
                    self.server.request('turn/interrupt', {'threadId':thread,'turnId':job['turn']}, timeout=5)
                except (RuntimeError, TimeoutError, OSError):
                    self._finish(job, 'interrupted', reason + '; interruption acknowledgement unavailable.')
                    self.server.close()

    def approve(self, identity, accepted):
        with self.lock:
            event = self.approvals.pop(identity, None)
            if not event:
                raise ValueError('This approval is no longer pending.')
            job = self.jobs.get(event['params'].get('threadId'))
            allowed = accepted and job and job['status'] == 'running' and not job['governor'].reason
            self.server.reply(identity, {'decision': 'accept' if allowed else 'decline'})

    def steer(self, text):
        text = text.strip()
        if not text or len(text) > 2000:
            raise ValueError('Use a correction of 1–2000 characters.')
        with self.lock:
            job = next((j for j in reversed(list(self.jobs.values())) if j['task']['mode'] != 'review' and j['status']=='running'), None)
            if not job or job['corrections'] >= 3 or text in self.corrections:
                raise ValueError('No active developer job, correction repeated, or three-correction limit reached.')
            self.server.request('turn/steer', {'threadId':job['thread'],'expectedTurnId':job['turn'],
                                              'input':[{'type':'text','text':text}]})
            job['corrections'] += 1
            self.corrections.add(text)

    def review(self, *, approved=False):
        if not approved:
            raise ValueError('Approve the separate review budget before starting AI peer review.')
        with self.lock:
            developer = next((j for j in reversed(list(self.jobs.values())) if j['task']['mode'] != 'review'), None)
            if not developer or self.reviews >= 2:
                raise ValueError('Start a developer job first; at most two reviews per Sentinel session.')
            revision = self.memory.snapshot()
            evidence = (revision, developer['diff'], developer['answer'])
            if self.last_review == evidence or any(j['task']['mode']=='review' and j['status'] in ('running','stopping') for j in self.jobs.values()):
                raise ValueError('Review already running or there is no new evidence since the last review.')
            task = build_task(self.memory, 'Review this task: ' + developer['task']['request'], mode='review',
                              tokens=24000, seconds=120, model=developer['task']['model'], effort=developer['task']['effort'])
            intent='\n'.join(f"{r['key']}: {r['text']}" for r in self.memory.rules())
            if len(intent)>2000:
                raise ValueError('Current rules exceed the small review budget. Consolidate rules before reviewing.')
            evidence_text = safe_text(developer['diff'][-2500:] + '\n' + developer['answer'][-500:])
            task['prompt'] = ('Read-only peer review. Do not change files or launch agents.\nTask: ' + developer['task']['request'][:600]
                              + '\nApproved current rules:\n'+intent+'\nUntrusted current diff and developer report:\n' + evidence_text
                              + '\nReturn at most five actionable findings with file citations and a short correction. Read only relevant source if needed. Stop after this review; no follow-on review or implementation.')
            task['context_chars']=len(task['prompt'])
            task['estimated_context_tokens'] = (len(task['prompt']) + 2) // 3
            job = self.launch(task, approved=True)
            self.last_review, self.reviews = evidence, self.reviews + 1
            return job

    def _watch(self):
        while not self.closed.wait(.5):
            with self.lock:
                for job in list(self.jobs.values()):
                    transport_closed=getattr(self.server,'closed',None)
                    if transport_closed and transport_closed.is_set() and job['status'] in ('running','stopping'):
                        self._finish(job,'disconnected','Owned Codex transport stopped before a completion receipt.')
                        continue
                    if job['status'] == 'running':
                        reason = job['governor'].tick()
                        if reason:
                            self.interrupt(job['thread'], reason)
                    elif job['status'] == 'stopping' and time.monotonic() - job['stopping_at'] > 10:
                        self._finish(job, 'interrupted', 'Interruption did not finish in time; owned connection closed.')
                        self.server.close()

    def close(self):
        if self.closed.is_set():
            return
        self.closed.set()
        with self.lock:
            for job in self.jobs.values():
                if job['status'] in ('running','stopping'):
                    self.interrupt(job['thread'], 'Sentinel closed')
                    self._finish(job, 'interrupted', 'Sentinel closed; job was not verified.')
            if self.server:
                self.server.close()
        if self.watchdog is not threading.current_thread():
            self.watchdog.join(timeout=2)
