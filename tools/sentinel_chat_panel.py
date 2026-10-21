"""Tk panel for optional, user-triggered ChatGPT sign-in and diagnostic conversation."""
from __future__ import annotations
import queue
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import webbrowser
from sentinel_chatgpt import AccountStore, ChatGPTClient, ChatGPTError, LoginAttempt, INSTRUCTIONS, evidence_message
from sentinel_explanations import report_explanation, verified_resolution


class ChatPanel(tk.Frame):
    def __init__(self, parent, report_provider, *, store=None):
        super().__init__(parent, bg='#121d2d')
        self.provider = report_provider
        self.closed = threading.Event()
        self.cancelled = threading.Event()
        self.attempt = None
        self.busy = False
        self.events = queue.Queue(maxsize=32)
        self.models = []
        self.accounts = []
        self.history = []
        self.incident_key = None
        self.current_report = None
        self.display = ''
        self.ai_prefix = ''
        self.cache = {}
        self.account_var = tk.StringVar()
        self.model_var = tk.StringVar()
        self.message_var = tk.StringVar()
        self.status = tk.StringVar(value='Optional connection. Monitoring and local explanations work without sign-in.')
        self.store = None
        try:
            self.store = store or AccountStore()
            self.client = ChatGPTClient(self.store)
        except (ChatGPTError, OSError):
            self.status.set('Protected ChatGPT storage is unavailable. Local monitoring and explanations still work.')
        self._build()
        self._accounts()
        self.timer = self.after(150, self.poll)

    def _label(self, parent, text, color='#94a7c0', **kwargs):
        return tk.Label(parent, text=text, fg=color, bg='#121d2d', font=('Segoe UI', 9), **kwargs)

    def _build(self):
        account_bar = tk.Frame(self, bg='#121d2d')
        account_bar.pack(fill='x', padx=14, pady=(12, 5))
        self.connect_button = tk.Button(account_bar, text='Continue with ChatGPT', command=self.connect,
                                        fg='#111111', bg='#ffffff', activebackground='#e6e6e6', relief='flat', padx=14, pady=8,
                                        font=('Segoe UI Semibold', 10))
        self.connect_button.pack(side='left', padx=(0, 8))
        self.account_box = ttk.Combobox(account_bar, textvariable=self.account_var, state='readonly', width=31)
        self.account_box.pack(side='left', padx=(0, 6))
        self.account_box.bind('<<ComboboxSelected>>', self.select_account)
        ttk.Button(account_bar, text='Add account', command=lambda: self.connect(new=True)).pack(side='left', padx=(0, 6))
        self.disconnect_button = ttk.Button(account_bar, text='Sign out', command=self.disconnect)
        self.disconnect_button.pack(side='left')
        ttk.Button(account_bar, text='Manage usage', command=lambda: webbrowser.open('https://chatgpt.com/settings/usage')).pack(side='right')

        self._label(self, 'Uses your ChatGPT plan, sharing Work/Codex limits. Sends selected report evidence only when you ask.', anchor='w').pack(fill='x', padx=14, pady=(2, 5))
        controls = tk.Frame(self, bg='#121d2d')
        controls.pack(fill='x', padx=14, pady=(0, 7))
        self._label(controls, 'Model:').pack(side='left', padx=(0, 7))
        self.model_box = ttk.Combobox(controls, textvariable=self.model_var, state='readonly', width=30)
        self.model_box.pack(side='left', padx=(0, 8))
        self.refresh_models_button = ttk.Button(controls, text='Load models', command=self.load_models)
        self.refresh_models_button.pack(side='left', padx=(0, 8))
        self.analyze_button = ttk.Button(controls, text='Explain with ChatGPT', style='Primary.TButton', command=self.analyze)
        self.analyze_button.pack(side='left', padx=(0, 8))
        self.cancel_button = ttk.Button(controls, text='Cancel', command=self.cancel)
        self.cancel_button.pack(side='left')
        self.plan_label = self._label(controls, 'Not connected', '#69bcff')
        self.plan_label.pack(side='right')

        output = tk.Frame(self, bg='#0e1725')
        scroll = ttk.Scrollbar(output)
        scroll.pack(side='right', fill='y')
        self.text = tk.Text(output, bg='#0e1725', fg='#e7eef8', font=('Segoe UI', 11), wrap='word', relief='flat',
                            padx=15, pady=12, yscrollcommand=scroll.set, selectbackground='#254467')
        self.text.pack(fill='both', expand=True)
        scroll.configure(command=self.text.yview)
        self.show('Choose an incident to see a local explanation.\n\nTo discuss it here, connect your personal ChatGPT account and choose an available model.\n\nThere are no automatic background AI requests or separate API-key charges. Your plan settings can allow credit use; review Manage usage.')
        composer = tk.Frame(self, bg='#121d2d')
        composer.pack(side='bottom', fill='x', padx=14, pady=8)
        self.entry = tk.Entry(composer, textvariable=self.message_var, bg='#0e1725', fg='#e7eef8', insertbackground='#69bcff',
                              relief='flat', font=('Segoe UI', 11))
        self.entry.pack(side='left', fill='x', expand=True, ipady=8, padx=(0, 8))
        self.entry.bind('<Return>', lambda _event: self.ask())
        self.send_button = ttk.Button(composer, text='Ask follow-up', command=self.ask)
        self.send_button.pack(side='right')
        self._label(self, '', anchor='w', textvariable=self.status, wraplength=1000).pack(fill='x', padx=14, pady=(0, 8))
        output.pack(fill='both', expand=True, padx=14)

    def show(self, text):
        self.display = text
        self.text.configure(state='normal')
        self.text.delete('1.0', 'end')
        self.text.insert('1.0', text)
        self.text.configure(state='disabled')
        self.text.see('1.0')

    def set_report(self, row):
        if self.busy or not row:
            return
        key = (row['data']['id'], row['data']['count'], bool(row.get('resolved')), str((row.get('resolution') or {}).get('resolved_at', '')))
        if key != self.incident_key:
            self.incident_key = key
            self.current_report = row
            self.history = []
            self.show('SENTINEL · Explained on your computer\n\n' + report_explanation(row))

    def _evidence(self):
        row = self.current_report
        return evidence_message(row['data'], row['path'], row.get('resolution') if verified_resolution(row) else None)

    def _accounts(self):
        if self.store is None:
            return
        self.accounts = list(self.store.state['accounts'])
        labels = [self.store.state['accounts'][key].get('email', 'ChatGPT account') + ' · ' + key[-6:] for key in self.accounts]
        self.account_box.configure(values=labels)
        active = self.store.state.get('active')
        if active in self.accounts:
            self.account_box.current(self.accounts.index(active))
        account = self.store.account() or {}
        usable = bool(account.get('access_token') and 'chatgpt.tokens.use.direct' in account.get('scopes', []))
        self.plan_label.configure(text='Using ChatGPT plan' if usable else 'Not connected')

    def _busy(self, value):
        self.busy = value
        state = 'disabled' if value else 'normal'
        for button in (self.connect_button, self.disconnect_button, self.refresh_models_button, self.analyze_button, self.send_button):
            button.configure(state=state)
        self.account_box.configure(state='disabled' if value else 'readonly')
        self.model_box.configure(state='disabled' if value else 'readonly')

    def _emit(self, kind, value):
        if self.closed.is_set():
            return
        if kind == 'progress':
            try:
                self.events.put_nowait((kind, value))
            except queue.Full:
                pass
        else:
            while not self.closed.is_set():
                try:
                    self.events.put((kind, value), timeout=.2)
                    break
                except queue.Full:
                    continue

    def _run(self, kind, function):
        if self.busy:
            return
        self._busy(True)
        self.cancelled.clear()

        def worker():
            try:
                result = function()
                self._emit(kind, result)
            except ChatGPTError as error:
                self._emit('error', str(error))
            except Exception:
                # No raw exceptions, account records or headers in diagnostics/UI.
                self._emit('error', 'The ChatGPT operation did not complete. Local monitoring continues; try reconnecting if needed.')
        threading.Thread(target=worker, name='SentinelChatGPT', daemon=True).start()

    def connect(self, new=False):
        if self.store is None:
            self.status.set('Protected account storage is unavailable. Check the connection setup guide.')
            return
        def sign_in():
            self.attempt = LoginAttempt(self.store, None if new else self.store.account())
            try:
                record = self.attempt.run()
                models = self.client.models() if 'chatgpt.tokens.use.direct' in record['scopes'] else []
                return models
            finally:
                self.attempt = None
        self.status.set('Complete sign-in and review plan permission in your browser. Cancel here to stop.')
        self._run('connected', sign_in)

    def select_account(self, _event=None):
        if self.busy or self.store is None:
            return
        index = self.account_box.current()
        if index >= 0:
            self.store.select(self.accounts[index])
            self.models = []
            self.model_var.set('')
            self.model_box.configure(values=[])
            self.history = []
            self.cache.clear()
            self._accounts()
            self.load_models()

    def load_models(self):
        if self.store:
            self.status.set('Checking models available to the selected ChatGPT account…')
            self._run('models', self.client.models)

    def _models(self, models):
        self.models = models
        self.model_box.configure(values=[m['display_name'] for m in models])
        # Respect the requested GPT-5.6 if it is actually present in this account's catalog.
        preferred = next((i for i, m in enumerate(models) if m['slug'] in ('gpt-5.6', 'gpt-5.6-sol')), 0)
        if models:
            self.model_box.current(preferred)
            self.status.set('Connected. Choose a model, then Explain with ChatGPT. Requests use your shared plan allowance.')
        else:
            self.model_var.set('')
            self.status.set('No eligible models were returned. Review ChatGPT plan permission or reconnect.')

    def _model(self):
        index = self.model_box.current()
        if index < 0 or index >= len(self.models):
            self.status.set('Load and select a model available to your account first.')
            return None
        return self.models[index]['slug']

    def analyze(self):
        if self.busy:
            return
        self.set_report(self.provider())
        model = self._model()
        if not self.current_report or not model:
            if not self.current_report:
                self.status.set('Select an incident first. No report was sent.')
            return
        cache_key = (self.incident_key, model)
        if cache_key in self.cache:
            self.show('CHATGPT EXPLANATION — cached for this incident occurrence count\n\n' + self.cache[cache_key])
            self.history = [self._evidence(), {'role': 'assistant', 'content': self.cache[cache_key][:6000]}]
            self.status.set('Reused the completed explanation; no new AI request.')
            return
        self.history = [self._evidence()]
        self.ai_prefix = 'CHATGPT EXPLANATION — analysis of supplied evidence\n\n'
        self.show(self.ai_prefix + 'Reading the report…')
        self.status.set('Sending the selected report and bounded evidence to OpenAI using your ChatGPT plan…')
        def request():
            answer = self.client.answer(model, INSTRUCTIONS, list(self.history), lambda text: self._emit('progress', text), self.cancelled)
            return {'text': answer, 'cache_key': cache_key}
        self._run('answer', request)

    def ask(self):
        if self.busy:
            return
        question = self.message_var.get().strip()[:2000]
        if not question:
            return
        self.set_report(self.provider())
        model = self._model()
        if not self.current_report or not model:
            return
        if not self.history:
            self.history = [self._evidence()]
        self.history = self.history[:1] + self.history[1:][-6:]
        self.history.append({'role': 'user', 'content': question})
        self.message_var.set('')
        self.ai_prefix = 'YOU\n' + question + '\n\nSENTINEL / CHATGPT\n'
        self.show(self.ai_prefix + 'Thinking…')
        self.status.set('Answering with your ChatGPT plan…')
        self._run('answer', lambda: {'text': self.client.answer(model, INSTRUCTIONS, list(self.history), lambda text: self._emit('progress', text), self.cancelled), 'cache_key': None})

    def disconnect(self):
        if self.store:
            self.status.set('Signing out of the selected connection…')
            self._run('disconnected', self.client.disconnect)

    def cancel(self):
        self.cancelled.set()
        if self.attempt:
            self.attempt.cancelled.set()
        self.status.set('Cancellation requested. Local monitoring continues.')

    def poll(self):
        if self.closed.is_set():
            return
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == 'progress':
                self.show(self.ai_prefix + value)
                continue
            self._busy(False)
            self._accounts()
            if kind in ('models', 'connected'):
                if kind == 'connected':
                    self.history = []
                    self.cache.clear()
                self._models(value)
                account = self.store.account() or {}
                if kind == 'connected' and value and not account.get('welcomed'):
                    messagebox.showinfo('You’re using your ChatGPT plan', 'Eligible AI requests in Sentinel use your ChatGPT plan, sharing Work/Codex limits. You can manage usage and credit settings in ChatGPT Settings → Usage.\n\nMonitoring remains local. Only the report you ask to analyze is sent to OpenAI.')
                    account['welcomed'] = True
                    self.store.save()
            elif kind == 'answer':
                self.show(self.ai_prefix + value['text'])
                self.history.append({'role': 'assistant', 'content': value['text'][:6000]})
                if value.get('cache_key'):
                    if len(self.cache) >= 64:
                        del self.cache[next(iter(self.cache))]
                    self.cache[value['cache_key']] = value['text']
                self.status.set('Explanation complete. It is an interpretation of the evidence, not a verified fix.')
            elif kind == 'disconnected':
                self.models = []
                self.model_var.set('')
                self.model_box.configure(values=[])
                self.history = []
                self.cache.clear()
                self.status.set('Signed out; monitoring continues.' if value else 'Signed out locally. Remote revocation was not confirmed; disconnect Sentinel in ChatGPT settings if needed.')
            elif kind == 'error':
                self.status.set(value)
                if self.ai_prefix:
                    self.show(self.display + '\n\nNOT COMPLETED\n' + value)
        self.timer = self.after(150, self.poll)

    def close(self):
        self.closed.set()
        self.cancel()
        if self.timer:
            self.after_cancel(self.timer)
