"""Native development assistant. All indexing/process/network work stays off Tk."""
from __future__ import annotations
import json
from pathlib import Path
import queue
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, filedialog, simpledialog
import webbrowser
import adc
from sentinel_assistant import build_task, choose_model, prepare_attachments
from sentinel_codex import AssistantController
from sentinel_memory import ProjectMemory, safe_text
from sentinel_chatgpt_pane import ChatGPTPane, implementation_requested

BG, FIELD, TEXT, MUTED = '#121d2d', '#0e1725', '#e7eef8', '#94a7c0'


class AssistantPanel(tk.Frame):
    def __init__(self, parent, project, *, state_path=None, start=True):
        super().__init__(parent, bg=BG)
        self.closed = threading.Event()
        self.work = queue.Queue(maxsize=16)
        self.events = queue.Queue(maxsize=256)
        self.progress_lock = threading.Lock()
        self.latest_progress = {}
        self.task, self.preview_inputs = None, None
        self.models, self.account = [], None
        self.memory, self.controller = None, None
        self.developer_thread = None
        self.busy = False
        self.question_pending = False
        self.active_question_thread = None
        self.question_cancel = threading.Event()
        self.attachments = []
        self.start_browser = start
        self.chat_browser = None
        self.chat_sending=False
        self.chat_send_timer=None
        self.chat_messages=[]
        self.route = tk.StringVar(value='ChatGPT conversation')
        self.credits = tk.StringVar(value='')
        self.credit_status = tk.StringVar(value='Codex idle. Purchased credit balance has not been read.')
        self.chat_status = tk.StringVar(value='ChatGPT conversation stays here. Sign in on the official page; choose normal Chat mode.')
        self.attachment_label = tk.StringVar(value='No extra evidence selected')
        self.mode = tk.StringVar(value='implement')
        self.model = tk.StringVar(value='Auto (catalog recommendation)')
        self.effort = tk.StringVar(value='medium')
        self.tokens = tk.StringVar(value='')  # Optional model-text diagnostic; never purchased credits.
        self.seconds = tk.StringVar(value='600')
        self.validation = tk.StringVar()
        self.status = tk.StringVar(value='Chat with ChatGPT here. Switch to Codex when you are ready to change the game.')
        self.memory_status = tk.StringVar(value='Local project memory updates in the background without AI.')
        self.usage = tk.StringVar(value='No Codex job running.')
        self._build()
        try:
            self.memory = ProjectMemory(project, state_path)
            self.controller = AssistantController(self.memory, callback=self.emit)
            preferences = self.memory.preferences()
            for key in ('seconds','effort','credits'):
                if key in preferences: getattr(self,key).set(str(preferences[key]))
        except Exception as error:
            self.status.set('Assistant memory unavailable; monitoring continues. ' + safe_text(error))
            return
        self.worker = threading.Thread(target=self._worker, daemon=True)
        self.worker.start()
        self.timer = self.after(100, self.poll)
        self.refresh_timer = self.after(15000, self._periodic) if start else None
        if start:
            self.submit('indexed', self.memory.refresh)

    def label(self, parent, text='', **kwargs):
        return tk.Label(parent, text=text, bg=BG, fg=MUTED, anchor='w', justify='left', **kwargs)

    def text(self, parent, height=5):
        frame = tk.Frame(parent, bg=FIELD)
        frame.pack(fill='both', expand=True)
        box = tk.Text(frame, height=height, bg=FIELD, fg=TEXT, insertbackground=TEXT,
                      wrap='word', relief='flat', font=('Segoe UI', 10), padx=8, pady=6)
        scroll = ttk.Scrollbar(frame, command=box.yview)
        box.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        box.pack(fill='both', expand=True)
        return box

    def _build(self):
        ttk.Label(self, textvariable=self.status, wraplength=850).pack(fill='x', padx=12, pady=(8, 5))
        self.views = ttk.Notebook(self)
        self.views.pack(fill='both', expand=True, padx=10, pady=(0, 8))
        ask, memory, rules, history, develop = [tk.Frame(self.views, bg=BG) for _ in range(5)]
        self.ask_page, self.advanced_page = ask, develop
        for page, title in zip((ask,memory,rules,history,develop), ('Conversation','Project memory','Rules & decisions','History','Advanced')):
            self.views.add(page, text=title)

        route_bar=tk.Frame(ask,bg=BG)
        route_bar.pack(fill='x',pady=5)
        for title in ('ChatGPT conversation','Codex implementation'):
            ttk.Radiobutton(route_bar,text=title,variable=self.route,value=title,command=self.switch_route).pack(side='left',padx=5)
        ttk.Button(route_bar,text='Refresh Codex balance',command=self.refresh_balance).pack(side='right')
        ttk.Label(ask,textvariable=self.credit_status,wraplength=850).pack(fill='x',pady=(0,3))
        self.chat_page=tk.Frame(ask,bg=BG)
        self.coding_page=tk.Frame(ask,bg=BG)
        self.chat_page.pack(fill='both',expand=True)
        self.label(self.chat_page,'Ask about your game. Your conversation uses normal ChatGPT; coding starts only in Codex.').pack(fill='x',pady=(8,4))
        request_frame=tk.Frame(self.chat_page,bg=BG)
        request_frame.pack(fill='x')
        self.chat_request=self.text(request_frame,height=3)
        self.chat_request.bind('<Return>',self._enter_chat)
        chat_bar=tk.Frame(self.chat_page,bg=BG)
        chat_bar.pack(fill='x')
        self.chat_send=ttk.Button(chat_bar,text='Send to ChatGPT',style='Primary.TButton',command=self.send_chat)
        self.chat_send.pack(side='left')
        ttk.Button(chat_bar,text='Stop',command=self.stop_chat).pack(side='left',padx=5)
        ttk.Button(chat_bar,text='ChatGPT sign-in / website',command=self.show_chat_website).pack(side='right')
        self.chat_answer=self.text(self.chat_page,height=7)
        self.set_text(self.chat_answer,'Type your question above and select Send to ChatGPT.\n\nIf sign-in is needed, open ChatGPT sign-in / website. Answers appear here. No Codex job starts from this conversation.')
        self.chat_answer.configure(state='disabled')
        chat_bar=tk.Frame(self.chat_page,bg=BG)
        chat_bar.pack(fill='x',pady=4)
        ttk.Button(chat_bar,text='Open / retry ChatGPT',command=self.open_chat).pack(side='left')
        self.chat_transfer=ttk.Button(chat_bar,text='Use this conversation in Codex',command=self.handoff_chat)
        self.chat_transfer.pack(side='left',padx=5)
        ttk.Button(chat_bar,text='Add game context',command=self.add_game_context).pack(side='left')
        ttk.Button(chat_bar,text='Reset website zoom',command=self.reset_chat_zoom).pack(side='left',padx=5)
        chat_bar.pack_configure(before=self.chat_answer.master)
        ttk.Label(self.chat_page,textvariable=self.chat_status,wraplength=850).pack(fill='x',pady=4)
        self.chat_window=tk.Toplevel(self)
        self.chat_window.title('Sentinel — ChatGPT website and sign-in')
        self.chat_window.geometry('1000x750')
        self.chat_window.protocol('WM_DELETE_WINDOW',self.chat_window.withdraw)
        self.chat_window.withdraw()
        self.chat_surface=tk.Frame(self.chat_window,bg=FIELD)
        self.chat_surface.pack(fill='both',expand=True)
        self.chat_page.bind('<Map>',lambda _:self.open_chat(retry=False) if self.start_browser and not self.chat_browser else None)
        self.label(self.chat_page,'Use normal Chat mode on the ChatGPT page. Its own limits apply. Sentinel never sends this chat to Codex automatically.').pack(fill='x',pady=4)
        ask=self.coding_page
        self.label(ask, 'Describe a coding task, or bring over the conversation. Preparation is local and uses no AI.').pack(fill='x', pady=(8, 4))
        request_frame = tk.Frame(ask, bg=BG)
        request_frame.pack(fill='x')
        self.request_box = self.text(request_frame, height=3)
        self.request_box.bind('<Return>', self._enter_question)
        self.request_box.bind('<Shift-Return>', lambda _: None)
        actions=tk.Frame(ask,bg=BG)
        actions.pack(fill='x',pady=6)
        self.ask_button=ttk.Button(actions,text='Prepare Codex task',style='Primary.TButton',command=self.ask_question)
        self.ask_button.pack(side='left')
        self.label(actions,'Credits per stage:').pack(side='left',padx=(8,2))
        ttk.Entry(actions,textvariable=self.credits,width=6).pack(side='left')
        ttk.Button(actions,text='Stop',command=self.stop).pack(side='left',padx=5)
        ttk.Button(actions,text='Add evidence…',command=self.add_evidence).pack(side='left',padx=5)
        ttk.Button(actions,text='Coding tasks & settings',command=lambda:self.views.select(develop)).pack(side='right')
        self.question_progress=ttk.Progressbar(ask,mode='indeterminate')
        self.question_progress.pack(fill='x',pady=(0,5))
        self.answer_box=self.text(ask,height=7)
        self.set_text(self.answer_box,'Codex changes your game using your Work/Codex allowance.\n\nPrepare the task, choose a credit budget, and review it before starting. Ordinary conversation is on ChatGPT conversation.')
        self.answer_box.configure(state='disabled')
        ttk.Label(ask,textvariable=self.usage,wraplength=850).pack(fill='x',pady=(4,0))
        self.label(ask,'Codex only starts after Review & run stage. Enter prepares; Shift+Enter adds a line.').pack(fill='x',pady=(2,5))

        self.label(develop,'Review the prepared Codex task here. Credit estimates may arrive late; this is a stop threshold, not a guaranteed billing cap.').pack(fill='x',pady=(6,2))

        top = tk.Frame(develop, bg=BG)
        top.pack(fill='x', pady=5)
        ttk.Button(top, text='Connect Codex', command=self.connect).pack(side='left')
        ttk.Button(top, text='Sign in', command=self.sign_in).pack(side='left', padx=5)
        self.model_box = ttk.Combobox(top, textvariable=self.model, state='readonly', width=32)
        self.model_box.pack(side='left', padx=5)
        self.model_box['values'] = ['Auto (catalog recommendation)']
        self.model_box.bind('<<ComboboxSelected>>', self._model_changed)
        self.effort_box = ttk.Combobox(top, textvariable=self.effort, state='readonly', width=9, values=['low','medium'])
        self.effort_box.pack(side='left', padx=5)
        ttk.Button(top, text='Choose Codex…', command=lambda: self.connect(choose=True)).pack(side='right')

        limits = tk.Frame(develop, bg=BG)
        limits.pack(fill='x', pady=5)
        ttk.Combobox(limits, textvariable=self.mode, state='readonly', width=12, values=['implement','question','audit']).pack(side='left')
        self.label(limits, ' Codex credits per stage').pack(side='left')
        ttk.Entry(limits, textvariable=self.credits, width=8).pack(side='left', padx=4)
        self.label(limits, 'Time (seconds)').pack(side='left')
        ttk.Entry(limits, textvariable=self.seconds, width=6).pack(side='left', padx=4)
        ttk.Button(limits, text='Prepare locally', command=self.prepare).pack(side='right')
        validate = tk.Frame(develop, bg=BG)
        validate.pack(fill='x', pady=(0, 5))
        self.label(validate, 'Optional validation (JSON command):').pack(side='left')
        ttk.Entry(validate, textvariable=self.validation).pack(side='left', fill='x', expand=True, padx=5)
        evidence = tk.Frame(develop, bg=BG)
        evidence.pack(fill='x', pady=(0,4))
        ttk.Button(evidence, text='Add evidence…', command=self.add_evidence).pack(side='left')
        ttk.Button(evidence, text='Clear evidence', command=self.clear_evidence).pack(side='left', padx=5)
        ttk.Label(evidence, textvariable=self.attachment_label).pack(side='left')

        self.preview = self.text(develop, height=6)
        self.preview.insert('1.0', 'Prepare locally to see relevant source, current rules and a compact coding task.\n\nLarge requests begin with a read-only audit. Every stage has a stopping point.\nNo job starts until you review its model, scope and budget.')
        buttons = tk.Frame(develop, bg=BG)
        buttons.pack(fill='x', pady=5)
        self.run_button = ttk.Button(buttons, text='Review & run stage', command=self.run_task, state='disabled')
        self.run_button.pack(side='left')
        ttk.Button(buttons, text='Stop jobs', command=self.stop).pack(side='left', padx=5)
        ttk.Button(buttons, text='Peer review', command=self.review).pack(side='left', padx=5)
        ttk.Button(buttons, text='Run validation', command=self.validate).pack(side='left', padx=5)
        ttk.Label(develop, textvariable=self.usage, wraplength=850).pack(fill='x')
        corrections = tk.Frame(develop, bg=BG)
        corrections.pack(fill='x', pady=5)
        self.correction = tk.StringVar()
        ttk.Entry(corrections, textvariable=self.correction).pack(side='left', fill='x', expand=True)
        ttk.Button(corrections, text='Send correction', command=self.steer).pack(side='right', padx=(6,0))

        search = tk.Frame(memory, bg=BG)
        ttk.Label(memory,textvariable=self.memory_status,wraplength=850).pack(fill='x',pady=(6,0))
        search.pack(fill='x', pady=8)
        self.query = tk.StringVar()
        ttk.Entry(search, textvariable=self.query).pack(side='left', fill='x', expand=True)
        ttk.Button(search, text='Search locally', command=self.search).pack(side='left', padx=5)
        ttk.Button(search, text='Refresh index', command=lambda: self.submit('indexed', self.memory.refresh)).pack(side='left')
        self.knowledge = self.text(memory, height=15)

        rule_bar = tk.Frame(rules, bg=BG)
        rule_bar.pack(fill='x', pady=8)
        ttk.Button(rule_bar, text='Propose rule', command=self.propose_rule).pack(side='left')
        ttk.Button(rule_bar, text='Approve selected', command=self.approve_rule).pack(side='left', padx=5)
        ttk.Button(rule_bar, text='Restore old version', command=self.restore_rule).pack(side='left', padx=5)
        ttk.Button(rule_bar, text='Refresh', command=self.load_rules).pack(side='right')
        self.label(rules, 'Proposals do not enter coding instructions. Approving a topic replaces its old rule; history is retained.').pack(fill='x')
        self.rules = ttk.Treeview(rules, columns=('topic','state','text'), show='headings', selectmode='browse')
        for column, width in [('topic',120),('state',100),('text',550)]:
            self.rules.heading(column, text=column.title())
            self.rules.column(column, width=width, stretch=column=='text')
        self.rules.pack(fill='both', expand=True, pady=6)
        self.rule_rows = {}
        self.rule_detail = self.text(rules, height=3)
        self.rules.bind('<<TreeviewSelect>>', lambda _: self._show_rule())

        bar = tk.Frame(history, bg=BG)
        bar.pack(fill='x', pady=8)
        ttk.Button(bar, text='Refresh saved history', command=self.load_history).pack(side='left')
        self.label(bar, 'Validation applies only to the selected command and current source.').pack(side='left', padx=8)
        self.history = self.text(history, height=20)

    def emit(self, event):
        if self.closed.is_set():
            return
        if event.get('type')=='progress':
            with self.progress_lock:
                self.latest_progress[event['thread']]=event
            return
        try:
            self.events.put(event, timeout=.2)
        except queue.Full:
            # Reports remain persisted even when UI updates fall behind.
            pass

    def submit(self, kind, operation):
        if self.closed.is_set() or not self.memory:
            return
        try:
            self.work.put_nowait((kind, operation))
        except queue.Full:
            self.status.set('Assistant is busy. Wait for the current local operation.')

    def _worker(self):
        while not self.closed.is_set():
            try: kind, operation = self.work.get(timeout=.2)
            except queue.Empty: continue
            try: self.emit({'type':kind,'value':operation()})
            except Exception as error: self.emit({'type':'error','value':safe_text(error)[:800],'operation':kind})

    def _periodic(self):
        if not self.closed.is_set():
            if self.work.empty():
                self.submit('indexed', self.memory.refresh)
            self.refresh_timer = self.after(15000, self._periodic)

    def inputs(self):
        return (self.request_box.get('1.0','end').strip(), self.mode.get(), self.credits.get(),
                self.seconds.get(), self.model.get(), self.effort.get(), self.validation.get())

    def switch_route(self):
        if self.route.get()=='ChatGPT conversation':
            self.coding_page.pack_forget()
            self.chat_page.pack(fill='both',expand=True)
            if self.start_browser: self.open_chat(retry=False)
            self.status.set('ChatGPT conversation. Codex starts only after you review a coding stage.')
        else:
            self.chat_page.pack_forget()
            self.coding_page.pack(fill='both',expand=True)
            self.status.set('Codex implementation. Enter a task and credit budget, then prepare it locally.')
        self.views.select(self.ask_page)

    def open_chat(self, retry=True):
        if not self.memory: return
        if not self.chat_browser:
            profile=self.memory.path.parent/'chatgpt-browser'
            self.chat_browser=ChatGPTPane(self.chat_surface,self._chat_event,profile)
            self.chat_status.set('Opening https://chatgpt.com inside Sentinel… Waiting for the page. No Codex request is made.')
        if retry:
            self.chat_status.set('Returning to https://chatgpt.com… Waiting for the page. No Codex request is made.')
            self.chat_browser.retry()
        else:
            # Showing the conversation or adding a draft must preserve its URL,
            # messages and composer. Only the explicit retry button navigates.
            self.chat_browser.start()

    def handoff_chat(self):
        if self.busy:
            self.status.set('Finish or stop the current Codex task before preparing another.')
            return
        existing=getattr(self,'transfer_window',None)
        if existing and existing.winfo_exists():existing.lift();return
        self.transfer_window=tk.Toplevel(self)
        self.transfer_window.title('Review conversation for Codex')
        self.transfer_window.geometry('850x600')
        self.label(self.transfer_window,'Review the captured conversation, or paste your ChatGPT conversation here. This step uses no Codex credits.').pack(fill='x',padx=10,pady=8)
        buttons=tk.Frame(self.transfer_window,bg=BG);buttons.pack(side='bottom',fill='x',padx=10,pady=8)
        ttk.Button(buttons,text='Use reviewed conversation',command=self.confirm_chat_transfer).pack(side='left')
        self.transfer_box=self.text(self.transfer_window,height=12)
        self.set_text(self.transfer_box,'\n\n'.join(r.get('role','')+': '+r.get('text','') for r in self.chat_messages))
        if self.chat_browser:self.chat_browser.command('handoff')

    def confirm_chat_transfer(self):
        from sentinel_chatgpt_pane import conversation_request
        text=self.transfer_box.get('1.0','end').strip()
        if not text:
            self.status.set('Paste or capture a conversation before transferring. No Codex request started.')
            return
        request=conversation_request('https://chatgpt.com/',[{'role':'user','text':text}])
        self.transfer_window.destroy()
        self._chat_event({'type':'handoff','request':request,'reviewed':True})

    def show_chat_website(self):
        self.open_chat(retry=False)
        if self.chat_browser:self.chat_browser.command('website')

    def reset_chat_zoom(self):
        self.open_chat(retry=False)
        if self.chat_browser:self.chat_browser.command('zoom_reset')

    def _enter_chat(self,event):
        if event.state & 1:return None
        self.send_chat()
        return 'break'

    def send_chat(self):
        if self.chat_sending:return
        text=self.chat_request.get('1.0','end').strip()
        if not text:
            self.chat_status.set('Type a question in the box above first.')
            return
        if implementation_requested(text):
            self.handoff_chat()
            return
        if len(text)>16000:
            self.chat_status.set('Keep one question under 16,000 characters.')
            return
        self.open_chat(retry=False)
        if not self.chat_browser:return
        self.chat_sending=True
        self.chat_send.state(['disabled'])
        self.chat_status.set('Sending your question to normal ChatGPT…')
        self.chat_browser.command('send',text=text)
        if self.chat_send_timer:self.after_cancel(self.chat_send_timer)
        self.chat_send_timer=self.after(20000,self._chat_send_timeout)

    def _chat_send_timeout(self):
        if self.closed.is_set() or not self.chat_sending:return
        self._chat_event({'type':'send_error','value':'No send confirmation arrived. Check the website before retrying to avoid sending twice.'})

    def stop_chat(self):
        if self.chat_browser:self.chat_browser.command('stop')

    def draft_chat(self,text):
        self.route.set('ChatGPT conversation')
        self.switch_route()
        previous=self.chat_request.get('1.0','end').strip()
        self.set_text(self.chat_request,(previous+'\n\n' if previous else '')+text[:16000])
        self.chat_status.set('Context added to your question. Review it, then select Send to ChatGPT.')

    def add_game_context(self):
        query=simpledialog.askstring('Relevant game context','What problem or game system should Sentinel look up?',parent=self)
        if not query or not self.memory: return
        def operation():
            self.memory.refresh()
            context=self.memory.context(query,max_chars=6000)
            intent='\n'.join(f"{r['key']}: {r['text']}" for r in self.memory.rules())[:2000]
            return (query[:2000]+'\n\nLocal game context (reference evidence; verify hypotheses before changing code):\n'
                    +(context or 'No matching indexed source found.')+'\n\nApproved project decisions:\n'+intent)
        self.submit('chat_draft',operation)

    def _chat_event(self,event):
        kind=event.get('type')
        if kind=='conversation':
            self.chat_messages=event.get('messages',[])
            if self.chat_messages:
                self.set_text(self.chat_answer,'\n\n'.join(('You' if r.get('role')=='user' else 'ChatGPT')+':\n'+r.get('text','') for r in self.chat_messages))
            return
        if kind in ('sent','send_error','stopped'):
            self.chat_sending=False
            self.chat_send.state(['!disabled'])
            self.chat_status.set(event['value'])
            if kind=='sent':self.set_text(self.chat_request,'')
            elif kind=='send_error':self.set_text(self.chat_answer,event['value'])
            return
        if kind=='handoff':
            preview=getattr(self,'transfer_window',None)
            if not event.get('reviewed') and preview and preview.winfo_exists():
                self.set_text(self.transfer_box,event['request'])
                return
            if self.busy:
                self.status.set('Conversation ready; finish or stop the current Codex task before transferring it again.')
                return
            self.set_text(self.request_box,event['request'])
            self.mode.set('implement')
            self.route.set('Codex implementation')
            self.switch_route()
            self.task=None
            self.run_button.state(['disabled'])
            self.set_text(self.answer_box,'Conversation brought over from ChatGPT.\n\nChoose credits per stage and select Prepare Codex task. No Codex inference has started.')
            self.status.set('Conversation ready for Codex. Choose a credit budget and prepare the task.')
        elif kind=='location':
            origin=event.get('value','')
            if origin=='https://chatgpt.com':
                self.chat_status.set('ChatGPT is loading. Waiting for its message box or sign-in page…')
            elif origin=='https://auth.openai.com':
                self.chat_status.set('ChatGPT sign-in is open. Complete sign-in on the embedded page.')
            else:
                self.chat_status.set('Embedded page: '+origin+'. Select Open / retry ChatGPT to return to the conversation.')
        elif kind=='attached':
            self.chat_status.set('Browser attached. Waiting for ChatGPT’s message box or sign-in page…')
        elif kind=='page_state':
            state=event.get('value') or {}
            if state.get('origin') and state['origin'] not in ('https://chatgpt.com','https://auth.openai.com'):
                self.chat_status.set('The browser has left ChatGPT. Select Open / retry ChatGPT to return and open the question box.')
            elif state.get('origin')=='https://auth.openai.com':
                self.chat_status.set('ChatGPT sign-in is open. Complete sign-in on the embedded page.')
            elif state.get('browser_visible') is False and self.chat_window.winfo_viewable():
                self.chat_status.set('The browser display is hidden. Select Open / retry ChatGPT to show it again.')
            elif state.get('challenge'):
                self.chat_status.set('ChatGPT is waiting for browser verification. Complete it on the page, then retry if needed.')
            elif state.get('composer') and state.get('composer_visible') is False and self.chat_window.winfo_viewable():
                self.chat_status.set('ChatGPT’s message box is outside the visible pane. Enlarge Sentinel or select Open / retry ChatGPT.')
            elif state.get('composer'):
                self.chat_status.set('ChatGPT’s message box is ready. Type your question above and select Send to ChatGPT.')
            elif state.get('sign_in'):
                self.chat_status.set('Sign in on the embedded ChatGPT page to open your conversation.')
            else:
                self.chat_status.set('ChatGPT’s message box is not ready. Wait for the page, or select Open / retry ChatGPT.')
        elif kind in ('error','drafted'):
            self.chat_status.set(event['value'])
            if kind=='error' and self.chat_sending:
                self.chat_sending=False
                self.chat_send.state(['!disabled'])
                self.set_text(self.chat_answer,event['value'])

    def _enter_question(self, event):
        if event.state & 1:  # Shift+Enter keeps the Text widget's normal newline.
            return None
        self.ask_question()
        return 'break'

    def _question_busy(self, value):
        self.busy=value
        self.ask_button.state(['disabled'] if value else ['!disabled'])
        if value: self.question_progress.start(12)
        else: self.question_progress.stop()

    def ask_question(self):
        if self.route.get()=='ChatGPT conversation':
            self.status.set('Use the ChatGPT page to chat. Switch to Codex implementation to prepare a coding task.')
            return
        if self.busy:
            return
        request=self.request_box.get('1.0','end').strip()
        if not request:
            self.status.set('Describe the coding task first, then select Prepare Codex task.')
            self.request_box.focus_set()
            return
        if not self.memory or not self.controller:
            self.status.set('Project memory is unavailable. Reopen Sentinel to retry.')
            self.set_text(self.answer_box,self.status.get())
            return
        credits,seconds,selected,effort=self.credits.get(),self.seconds.get(),self.model.get(),self.effort.get()
        if not credits.strip():
            self.status.set('Choose a Codex credit budget per stage first. These are credits, not model text tokens.')
            return
        values=self.inputs()
        attachments=list(self.attachments)
        self.question_pending=False
        self.question_cancel.clear()
        self.active_question_thread=None
        self._question_busy(True)
        self.status.set('Loading the Codex catalog and preparing locally. No model request is being made…')
        self.set_text(self.answer_box,'Preparing a local preview. Codex starts only after Review & run stage.')
        def operation():
            models,account=self.models,self.account
            server=self.controller.server
            disconnected=getattr(server,'closed',None)
            if not server or disconnected and disconnected.is_set() or not models or not account:
                connection=self.controller.connect()
                models,account=connection['models'],connection['account']
                self.emit({'type':'connected','value':connection})
            if self.question_cancel.is_set(): raise ValueError('Question cancelled before it was sent. No model request was started.')
            if not account or account.get('type')!='chatgpt':
                raise ValueError('ChatGPT sign-in is needed. Open Advanced → Sign in, complete the browser step, then ask again.')
            model,compatible=choose_model(models,request,history=self.memory.history())
            if not selected.startswith('Auto'):
                model=selected
                catalog=next((m for m in models if m.get('model',m['id'])==model),None)
                if not catalog: raise ValueError('The selected model is unavailable. Choose Auto in Advanced and retry.')
                supported=[e['reasoningEffort'] for e in catalog.get('supportedReasoningEfforts',[])]
                if effort not in supported: raise ValueError('Choose a supported reasoning setting in Advanced or use Auto.')
                compatible=effort
            task=build_task(self.memory,request,mode=values[1],credit_limit=credits,seconds=int(seconds),
                            model=model,effort=compatible,validation=json.loads(values[6]) if values[6].strip() else None,attachments=attachments)
            if self.question_cancel.is_set(): raise ValueError('Question cancelled before it was sent. No model request was started.')
            self.memory.save_preferences({'credits':credits,'seconds':int(seconds),'mode':values[1],'effort':compatible})
            return task,values
        self.submit('prepared',operation)

    def add_evidence(self):
        paths = filedialog.askopenfilenames(title='Select compact text evidence or screenshots',filetypes=[('Evidence','*.txt *.md *.gd *.py *.json *.png *.jpg *.jpeg *.webp')])
        if not paths: return
        def operation(): return prepare_attachments([a['path'] for a in self.attachments]+list(paths))
        self.submit('attachments',operation)

    def clear_evidence(self):
        self.attachments=[]
        self.task=None
        self.attachment_label.set('No extra evidence selected')
        self.run_button.state(['disabled'])

    def prepare(self):
        if self.busy:
            self.status.set('Finish or stop the current task before preparing another stage.')
            return
        self.views.select(self.advanced_page)
        values = self.inputs()
        self.task = None
        self.run_button.state(['disabled'])
        self.status.set('Building a compact task from local source…')
        def operation():
            request, mode, credits, seconds, selected, effort, validation = values
            argv = json.loads(validation) if validation.strip() else None
            model = None
            if self.models:
                recommended, compatible = choose_model(self.models, request, history=self.memory.history())
                model = recommended if selected.startswith('Auto') else selected
                catalog = next((m for m in self.models if m.get('model',m['id'])==model), None)
                if not catalog: raise ValueError('Choose a model from the connected catalog.')
                efforts = [v['reasoningEffort'] for v in catalog.get('supportedReasoningEfforts', [])]
                effort = compatible if selected.startswith('Auto') else effort
                if effort not in efforts: raise ValueError('Choose an effort supported by this model.')
            task = build_task(self.memory, request, mode=mode, credit_limit=credits or None, seconds=int(seconds),
                              model=model, effort=effort, validation=argv, attachments=list(self.attachments))
            self.memory.save_preferences({'credits':credits,'seconds':int(seconds),'mode':mode,'effort':effort})
            return task, values
        self.submit('prepared', operation)

    def connect(self, choose=False):
        if self.busy:
            self.status.set('Stop or finish the current task before reconnecting Codex.')
            return
        executable = None
        if choose:
            executable = filedialog.askopenfilename(title='Choose installed codex.exe', filetypes=[('Codex','codex.exe')])
            if not executable: return
        self.status.set('Connecting to installed Codex and loading its catalog…')
        self.submit('connected', lambda: self.controller.connect(executable))

    def refresh_balance(self):
        if self.controller and self.controller.server:
            self.submit('usage_refreshed',self.controller.refresh_account_usage)
        else: self.connect()

    def sign_in(self):
        if not self.controller or not self.controller.server:
            self.status.set('Connect Codex first, then use Sign in if needed.')
            return
        self.submit('login', lambda: self.controller.server.request('account/login/start', {'type':'chatgpt'}))

    def _model_changed(self, _=None):
        row = next((m for m in self.models if m.get('model',m['id'])==self.model.get()), None)
        efforts = [e['reasoningEffort'] for e in (row or {}).get('supportedReasoningEfforts', [])]
        self.effort_box['values'] = efforts or ['low','medium']
        if efforts and self.effort.get() not in efforts: self.effort.set(efforts[0])

    def run_task(self):
        if self.task and self.task.get('attachments',[]) != self.attachments:
            self.status.set('Evidence changed. Prepare the stage again before running it.')
            return
        if not self.task or self.preview_inputs != self.inputs():
            self.status.set('Inputs changed. Prepare the stage again before running it.')
            return
        task = dict(self.task)
        if not self.account or self.account.get('type') != 'chatgpt':
            self.status.set('A ChatGPT-backed Codex connection is required. Sign in and reconnect; API-key billing is not selected automatically.')
            return
        if not task.get('credit_limit_micros'):
            self.status.set('Choose a positive Codex credit budget, then prepare the stage again.')
            return
        if not messagebox.askyesno('Run reviewed Codex stage', f"{task['request'][:1500]}\n\n{task['mode']} · {task['model']} · {task['effort']}\nCredit stop threshold: {task['credit_limit']:g} Codex credits\nTime: {task['seconds']} seconds\n\nUses your Work/Codex allowance. Credits are separate from model text tokens. Usage estimates can arrive late; Sentinel cannot guarantee a hard billing cap.\n\nRun this stage?", parent=self):
            return
        self.run_button.state(['disabled'])
        self._question_busy(True)
        self.question_pending=True
        self.active_question_thread=None
        self.submit('launched', lambda: self.controller.launch(task, approved=True))

    def stop(self):
        self.question_cancel.set()
        self.status.set('Stopping… Any partial answer will remain visible.')
        def operation():
            for identity, job in list(self.controller.jobs.items()):
                if job['status'] == 'running': self.controller.interrupt(identity)
            return 'Stop requested. Waiting for completion receipts.'
        self.submit('message', operation)

    def review(self):
        credits=self.credits.get()
        if not credits.strip():
            self.status.set('Choose credits per stage before starting a separate paid review.')
            return
        if messagebox.askyesno('Peer review credit budget', f'Start one separate read-only Codex review?\n\nCredit stop threshold: {credits} credits; 120 seconds. Estimates can arrive late; this is not a hard billing cap.\nUses the developer job’s model. At most two reviews per session, with new evidence each time.', parent=self):
            self.submit('launched', lambda: self.controller.review(approved=True,credit_limit=credits))

    def steer(self):
        text = self.correction.get()
        self.submit('message', lambda: (self.controller.steer(text), 'Correction delivered to the active developer turn.')[1])

    def validate(self):
        if not self.developer_thread:
            self.status.set('Complete a stage with a validation command first.')
            return
        identity = self.developer_thread
        job = self.controller.jobs.get(identity)
        if job and messagebox.askyesno('Run selected local validation', 'Run this command against current source?\n\n' + json.dumps(job['task']['validation']) + '\n\nNo AI request is made.', parent=self):
            self.submit('validated', lambda: self.controller.validate(identity))

    def search(self):
        query = self.query.get()
        self.submit('search', lambda: self.memory.context(query) or 'No current source matches. Try a system or function name.')

    def load_rules(self): self.submit('rules', self.memory.rule_history)
    def load_history(self): self.submit('history', self.memory.history)

    def propose_rule(self):
        key = simpledialog.askstring('Rule topic','Topic, for example fishing progression:', parent=self)
        if not key: return
        text = simpledialog.askstring('Proposed rule','Describe the intended design (proposal until approved):', parent=self)
        if not text: return
        def operation():
            self.memory.propose_rule(key,text)
            return self.memory.rule_history()
        self.submit('rules',operation)

    def selected_rule(self):
        selected = self.rules.selection()
        return self.rule_rows.get(selected[0]) if selected else None

    def _show_rule(self):
        row = self.selected_rule()
        if row: self.set_text(self.rule_detail, f"{row['key']} · version {row['id']} · {row['status']}\n{row['text']}")

    def approve_rule(self):
        row = self.selected_rule()
        if not row or row['status']!='proposed':
            self.status.set('Select a proposed rule first.')
            return
        if messagebox.askyesno('Approve current design', f"{row['key']}\n\n{row['text']}\n\nReplace any currently approved rule for this topic? Earlier versions remain available.",parent=self):
            self.submit('rules',lambda: (self.memory.approve_rule(row['id']),self.memory.rule_history())[1])

    def restore_rule(self):
        row = self.selected_rule()
        if row and messagebox.askyesno('Restore rule version',f"Restore this previously approved intent as a new version?\n\n{row['text']}",parent=self):
            self.submit('rules',lambda: (self.memory.rollback_rule(row['id']),self.memory.rule_history())[1])

    def set_text(self, box, text):
        original=box.cget('state')
        box.configure(state='normal')
        box.delete('1.0','end')
        box.insert('1.0',str(text)[-30000:])
        box.configure(state=original)

    def poll(self):
        if self.closed.is_set(): return
        with self.progress_lock:
            progress=list(self.latest_progress.values())
            self.latest_progress.clear()
        for event in progress:
            try: self.events.put_nowait(event)
            except queue.Full: break
        for _ in range(80):
            try: event = self.events.get_nowait()
            except queue.Empty: break
            kind, value = event.get('type'), event.get('value')
            if kind == 'error':
                if event.get('operation')=='indexed':
                    self.memory_status.set('Local index refresh failed: '+value)
                    continue
                self.status.set('Could not complete the request. '+value)
                self.set_text(self.answer_box,'Sentinel could not complete this request.\n\n'+value+'\n\nReview the task and retry. Codex connection and sign-in options are under Advanced.')
                self.question_pending=False
                self._question_busy(False)
            elif kind == 'indexed': self.memory_status.set(f"Local memory: {value['files']} source files; {value['read']} read, {value['updated']} changed, {value['removed']} removed. No AI used.")
            elif kind == 'connected':
                self.models, self.account = value['models'], value['account']
                self.model_box['values'] = ['Auto (catalog recommendation)'] + [m.get('model',m['id']) for m in self.models]
                self.task = None
                self.run_button.state(['disabled'])
                if not self.question_pending:
                    self.status.set('Codex connected. Preparing and connecting use no model inference.')
                if value.get('usage'): self._account_usage(value['usage'])
            elif kind=='account_usage': self._account_usage(event['usage'])
            elif kind=='usage_refreshed': self._account_usage(value)
            elif kind=='chat_draft': self.draft_chat(value)
            elif kind=='ask_phase':
                if self.question_pending: self.status.set(value)
            elif kind == 'login':
                url = value.get('authUrl','')
                if url.startswith(('https://auth.openai.com/','https://chatgpt.com/')):
                    webbrowser.open(url)
                    self.status.set('Complete sign-in in your browser, then reconnect Codex. No tokens need copying.')
                else: self.status.set('Codex did not return a supported ChatGPT sign-in URL.')
            elif kind == 'prepared':
                self._question_busy(False)
                self.task, self.preview_inputs = value
                task = self.task
                self.set_text(self.preview, f"Model: {task['model'] or 'connect Codex to select'} · Effort: {task['effort']} · Mode: {task['mode']}\nCodex credit stop threshold: {task.get('credit_limit') if task.get('credit_limit') is not None else 'choose a budget'} · Time: {task['seconds']} seconds\nCredit estimates may arrive late; no hard billing cap is guaranteed.\nSuggested files: {', '.join(task['scope'])}\n\n{task['prompt']}")
                self.run_button.state(['!disabled'] if task['model'] else ['disabled'])
                self.status.set('Stage prepared locally. Review the scope, model and budget before running.')
                self.views.select(self.advanced_page)
            elif kind == 'attachments':
                self.attachments=value
                self.task=None
                self.run_button.state(['disabled'])
                self.attachment_label.set(f"{len(value)} unique files: " + ', '.join(Path(a['path']).name for a in value)[:80])
                self.status.set('Selected evidence is sent only with an approved stage. Review screenshots for private content.')
            elif kind == 'search': self.set_text(self.knowledge, value)
            elif kind == 'rules':
                self.rules.delete(*self.rules.get_children())
                self.rule_rows = {str(r['id']):r for r in value}
                for row in value: self.rules.insert('', 'end', iid=str(row['id']), values=(row['key'],row['status'],row['text'][:180]))
                self.task = None
                self.run_button.state(['disabled'])
                self.status.set('Rule history saved. Prepare again to use current approved intent.')
            elif kind == 'history':
                rows = []
                for row in value:
                    body, report = row['body'], row['body'].get('report',{})
                    verified = 'Selected validation passed on current source' if row['verified'] else 'Unverified, failed or source changed'
                    rows.append(f"#{row['id']} · {row['status']} · {row['request']}\n{verified}\nModel: {body.get('model','—')} · Observed tokens: {report.get('tokens')} · Commands: {report.get('commands',0)} · Repeats: {report.get('repeated_operations',0)}\n{json.dumps(report,ensure_ascii=False,indent=2)}\n{body.get('answer','')}\n{body.get('error','')}\n")
                passed=sum(row.get('validation_passed',False) for row in value)
                counts=[row['body'].get('report',{}).get('tokens') for row in value]
                observed=sum(n for n in counts if isinstance(n,int))
                summary=f"Recent records: {len(value)} · Successful selected validations: {passed} · Reported tokens across these records: {observed:,}\nModel recommendations can adapt after three measured validations in the same broad task category. These are observations, not a claim of quota savings.\n\n"
                self.set_text(self.history,summary + ('\n'.join(rows) or 'No jobs recorded yet. Source indexing never marks a feature verified.'))
            elif kind in ('job','launched','asked'):
                if kind in ('launched','asked') and value['task']['mode']!='review': self.developer_thread=value['thread']
                if self.question_pending and self.active_question_thread is None and kind in ('job','asked'):
                    self.active_question_thread=event.get('thread') if kind=='job' else value['thread']
                if kind=='job' or not value.get('finished'):
                    self.status.set('Sentinel is working… You can select Stop at any time.')
            elif kind=='progress':
                report=event['report']
                self.usage.set(self._credit_report(report))
                if self.question_pending and event['thread']==self.active_question_thread:
                    if event.get('answer'):
                        self.set_text(self.answer_box,event['answer'])
                        self.set_text(self.preview,'Codex is working…\n\n'+event['answer'])
                    if event.get('message'): self.status.set(event['message'])
            elif kind=='finished':
                body=event['body']
                self.usage.set(self._credit_report(body['report']))
                self.set_text(self.preview,f"{event['status'].upper()}\n\n{body['answer']}\n\n{body['error']}\n\nEfficiency report:\n{json.dumps(body['report'],indent=2)}\n\nNo next stage was started. Validation must be run and checked separately.")
                self.status.set('Stage ended; result and usage saved in local history.')
                if event['thread']==self.active_question_thread:
                    completed=event['status']=='completed'
                    text=body.get('answer','').strip()
                    if not text:
                        text='No answer was returned.' if completed else 'The question stopped before an answer was completed.'
                    if body.get('error'): text+='\n\n'+body['error']
                    if not completed: text+='\n\nReview the result before preparing another stage.'
                    self.set_text(self.answer_box,text)
                    self.question_pending=False
                    self._question_busy(False)
                    self.status.set('Codex stage completed. Result and credit estimate saved.' if completed else 'Codex stage stopped. See its result and credit estimate.')
            elif kind=='approval':
                accepted=messagebox.askyesno('Codex requests approval',safe_text(json.dumps(event['params'],indent=2))[:5000],parent=self)
                self.submit('message',lambda identity=event['id'], decision=accepted: (self.controller.approve(identity,decision),'Approval decision delivered.')[1])
            elif kind=='validated': self.set_text(self.preview,f"Validation exit: {value['exit_code']} · Timed out: {value['timed_out']}\n\n{value['output']}\n\nOpen History & efficiency for source freshness.")
            elif kind=='message': self.status.set(value)
        self.timer = self.after(100,self.poll)

    def _account_usage(self,usage):
        balance=usage.get('balance')
        shown=str(balance)+' credits' if balance is not None else 'unavailable'
        ordinary=usage.get('ordinary_usage_allowed')
        included='available' if ordinary is True else 'unavailable' if ordinary is False else 'not reported'
        self.credit_status.set(f'Purchased balance: {shown} · Included Work/Codex usage: {included}. Account-wide; other chats can use it.')

    @staticmethod
    def _credit_report(report):
        value=report.get('credits')
        source={'server_estimate':'account report estimate','published_rate_estimate':'published-rate estimate','awaiting_usage':'awaiting usage report'}.get(report.get('credit_source'),'unavailable')
        shown=f'{value:g}' if isinstance(value,(int,float)) else 'not reported'
        limit=report.get('credit_budget')
        return (f'Codex credits estimated: {shown} / {limit if limit is not None else "no budget"} ({source}) · Commands: {report.get("commands",0)} · Files: {len(report.get("files",[]))}\n'
                'Updates can arrive late; the credit threshold is not a guaranteed billing cap.\n'+'\n'.join(report.get('warnings',[])[-2:]))

    def close(self):
        if self.closed.is_set(): return
        self.question_progress.stop()
        self.closed.set()
        if self.chat_send_timer:self.after_cancel(self.chat_send_timer)
        if self.chat_browser: self.chat_browser.close()
        self.chat_window.destroy()
        if hasattr(self,'timer'): self.after_cancel(self.timer)
        if getattr(self,'refresh_timer',None): self.after_cancel(self.refresh_timer)
        if self.controller: self.controller.close()
        if hasattr(self,'worker'): self.worker.join(timeout=25)
        if self.memory and (not hasattr(self,'worker') or not self.worker.is_alive()): self.memory.close()
