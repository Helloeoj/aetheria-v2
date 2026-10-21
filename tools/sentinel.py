"""Independent ADC companion with optional user-authorized ChatGPT explanations."""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import os
from pathlib import Path
import queue
import sys
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import adc
from sentinel_monitor import Monitor
from sentinel_windows import SingleInstance, make_icon
from sentinel_chat_panel import ChatPanel
from sentinel_roadmap_panel import RoadmapPanel
from sentinel_explanations import incident_title, incident_area, report_explanation, verified_resolution

BG = '#0b111c'
PANEL = '#121d2d'
FIELD = '#0e1725'
TEXT = '#e7eef8'
MUTED = '#94a7c0'
BLUE = '#69bcff'
GREEN = '#71dcc0'
AMBER = '#ffcb7c'


class SentinelApp:
    def __init__(self, window, monitor, start=True):
        self.window, self.monitor = window, monitor
        self.state = {'incidents': [], 'activity': [], 'log': [], 'open_count': 0, 'active': [], 'last_exit': None}
        self.selected = None
        self.report_signature = None
        self.log_signature = None
        self.activity_signature = None
        self.tree_signature = None
        self.closed = False
        self.status = tk.StringVar(value='Watching for Aetheria')
        self.filter = tk.StringVar(value='Unresolved')
        self.technical = tk.BooleanVar(value=False)
        self.settings_path = monitor.root / 'companion/settings.json'
        self.settings = adc.read_json(self.settings_path, {})
        if self.settings.get('godot') and Path(self.settings['godot']).is_file():
            monitor.engine = self.settings['godot']
        window.title('Aetheria Sentinel')
        window.configure(bg=BG)
        window.geometry('1100x650+55+25')
        window.minsize(920, 560)
        window.protocol('WM_DELETE_WINDOW', self.close)
        try:
            icon = monitor.root / 'companion/sentinel.ico'
            if not icon.is_file():
                make_icon(icon)
            window.iconbitmap(str(icon))
        except (OSError, tk.TclError):
            pass # Missing/unwritable icon must never stop observation.
        self._style()
        self._build()
        if start:
            monitor.start()
            self._tick()

    def _style(self):
        self.window.option_add('*Font', ('Segoe UI', 10))
        style = ttk.Style(self.window)
        style.theme_use('clam')
        style.configure('.', background=PANEL, foreground=TEXT, bordercolor=PANEL, lightcolor=PANEL, darkcolor=PANEL)
        style.configure('TButton', background='#23364e', foreground=TEXT, padding=(12, 8), borderwidth=0)
        style.map('TButton', background=[('active', '#304b6b'), ('disabled', '#172235')], foreground=[('disabled', '#65758b')])
        style.configure('Primary.TButton', background='#77c9ff', foreground='#0a1725', font=('Segoe UI Semibold', 10))
        style.map('Primary.TButton', background=[('active', '#a4ddff'), ('disabled', '#294457')])
        style.configure('TNotebook', background=BG, borderwidth=0)
        style.configure('TNotebook.Tab', background=BG, foreground=MUTED, padding=(19, 11))
        style.map('TNotebook.Tab', background=[('selected', PANEL)], foreground=[('selected', BLUE)])
        style.configure('Treeview', background=FIELD, fieldbackground=FIELD, foreground=TEXT, rowheight=32, borderwidth=0)
        style.configure('Treeview.Heading', background=PANEL, foreground=MUTED, relief='flat', padding=(6, 8))
        style.map('Treeview', background=[('selected', '#254467')], foreground=[('selected', TEXT)])
        style.configure('TCombobox', fieldbackground=FIELD, foreground=TEXT, background=PANEL, arrowcolor=BLUE)
        style.configure('TScrollbar', background='#2b3c53', troughcolor=FIELD, borderwidth=0, arrowcolor=MUTED)

    def label(self, parent, text='', color=TEXT, size=10, bold=False, **options):
        return tk.Label(parent, text=text, fg=color, bg=parent.cget('bg'), font=('Segoe UI Semibold' if bold else 'Segoe UI', size), **options)

    def _build(self):
        header = tk.Frame(self.window, bg=BG)
        header.pack(fill='x', padx=24, pady=(19, 12))
        brand = tk.Frame(header, bg=BG)
        brand.pack(side='left')
        self.label(brand, 'A E T H E R I A   /   S E N T I N E L', BLUE, 11, True).pack(anchor='w')
        self.label(brand, 'Your local stability companion', TEXT, 21, True).pack(anchor='w', pady=(2, 0))
        self.badge = self.label(header, '●  WATCHING', GREEN, 10, True)
        self.badge.pack(side='right', padx=(16, 0))
        self.label(header, 'Local monitoring · Optional ChatGPT connection', MUTED, 9).pack(side='right')

        cards = tk.Frame(self.window, bg=BG)
        cards.pack(fill='x', padx=24, pady=(0, 14))
        self.game_card, self.game_hint = self._card(cards, 'GAME', 'Not running', 'I will notice when it starts.', 0)
        self.incident_card, self.incident_hint = self._card(cards, 'ISSUES TO CHECK', '0', 'I will explain what the reports mean.', 1)
        self.exit_card, self.exit_hint = self._card(cards, 'LAST EXIT', 'No exit observed', 'Sentinel stays open when the game closes.', 2)

        self.tabs = ttk.Notebook(self.window)
        self.tabs.pack(fill='both', expand=True, padx=24)
        assistant = tk.Frame(self.tabs, bg=PANEL)
        incidents = tk.Frame(self.tabs, bg=PANEL)
        live = tk.Frame(self.tabs, bg=PANEL)
        self.tabs.add(assistant, text='Companion')
        self.tabs.add(incidents, text='Incidents')
        self.tabs.add(live, text='Live log')
        ai = tk.Frame(self.tabs, bg=PANEL)
        self.tabs.add(ai, text='Explain & chat')
        self.ai_panel = ChatPanel(ai, self._report_for_chat)
        self.ai_panel.pack(fill='both', expand=True)
        self.roadmap = RoadmapPanel(self.tabs, self.monitor.root / 'companion/roadmap-progress.json')
        self.tabs.add(self.roadmap, text='Roadmap')
        # Give the roadmap reading space without changing the monitoring views.
        def tab_changed(_event=None):
            if self.tabs.select() == str(self.roadmap):
                cards.pack_forget()
            elif not cards.winfo_manager():
                cards.pack(fill='x', padx=24, pady=(0, 14), before=self.tabs)
        self.tabs.bind('<<NotebookTabChanged>>', tab_changed)

        welcome = tk.Frame(assistant, bg=PANEL)
        welcome.pack(fill='x', padx=22, pady=(19, 14))
        self.greeting = self.label(welcome, 'Standing by.', TEXT, 20, True)
        self.greeting.pack(anchor='w')
        self.explanation = self.label(welcome, 'Start Aetheria whenever you are ready. I will keep watch, even when Godot is closed.', MUTED, 10, anchor='w', justify='left', wraplength=900)
        self.explanation.pack(anchor='w', fill='x', pady=(5, 0))
        welcome.bind('<Configure>', lambda event: self.explanation.configure(wraplength=max(1, event.width)))
        controls = tk.Frame(assistant, bg=PANEL)
        controls.pack(fill='x', padx=22, pady=(0, 16))
        self.launch_button = ttk.Button(controls, text='▶  Launch Aetheria', style='Primary.TButton', command=self.launch)
        self.launch_button.pack(side='left', padx=(0, 8))
        ttk.Button(controls, text='Copy for Codex', command=self.copy_latest).pack(side='left', padx=(0, 8))
        ttk.Button(controls, text='Open reports', command=self.open_reports).pack(side='left', padx=(0, 8))
        ttk.Button(controls, text='Background', command=self.background).pack(side='left')
        ttk.Button(controls, text='Explain latest', command=self.explain_latest).pack(side='left', padx=8)
        self.label(assistant, 'ACTIVITY', MUTED, 9, True).pack(anchor='w', padx=22, pady=(0, 6))
        activity_frame = tk.Frame(assistant, bg=FIELD)
        activity_frame.pack(fill='both', expand=True, padx=22, pady=(0, 18))
        self.activity = ttk.Treeview(activity_frame, columns=('time', 'type', 'event'), show='headings', selectmode='browse', height=5)
        for column, title, width in [('time', 'Time', 93), ('type', 'Type', 100), ('event', 'Observed activity', 680)]:
            self.activity.heading(column, text=title, anchor='w')
            self.activity.column(column, width=width, stretch=column == 'event')
        self.activity.pack(fill='both', expand=True)

        toolbar = tk.Frame(incidents, bg=PANEL)
        toolbar.pack(fill='x', padx=14, pady=12)
        choice = ttk.Combobox(toolbar, textvariable=self.filter, values=['Unresolved', 'All retained'], state='readonly', width=15)
        choice.pack(side='left')
        choice.bind('<<ComboboxSelected>>', lambda _: self._show_incidents(force=True))
        ttk.Button(toolbar, text='Copy for Codex', command=self.copy_selected).pack(side='left', padx=8)
        ttk.Button(toolbar, text='Explain this', command=self.explain_report).pack(side='left', padx=8)
        self.clear_button = ttk.Button(toolbar, text='Clear results', command=self.clear_results, state='disabled')
        self.clear_button.pack(side='left', padx=8)
        ttk.Button(toolbar, text='Refresh reports', command=lambda: self.request('prepare')).pack(side='right')
        split = tk.PanedWindow(incidents, bg=PANEL, sashwidth=7, orient='horizontal', bd=0)
        split.pack(fill='both', expand=True, padx=14, pady=(0, 14))
        tree_frame = tk.Frame(split, bg=FIELD)
        self.incidents = ttk.Treeview(tree_frame, columns=('system', 'count', 'error'), show='headings', selectmode='browse')
        for column, title, width in [('system', 'Area', 95), ('count', 'Times', 55), ('error', 'What happened', 260)]:
            self.incidents.heading(column, text=title, anchor='w')
            self.incidents.column(column, width=width, stretch=column == 'error')
        self.incidents.pack(fill='both', expand=True)
        self.incidents.bind('<<TreeviewSelect>>', self.select_incident)
        detail_frame = tk.Frame(split, bg=FIELD)
        details_toolbar = tk.Frame(detail_frame, bg=FIELD)
        details_toolbar.pack(fill='x', padx=10, pady=5)
        ttk.Checkbutton(details_toolbar, text='Technical details', variable=self.technical, command=self.render_detail).pack(side='left')
        ttk.Button(details_toolbar, text='Open JSON', command=self.open_detail).pack(side='right')
        self.detail = self._text(detail_frame)
        self.detail.configure(font=('Segoe UI', 11))
        split.add(tree_frame, width=420, minsize=250)
        split.add(detail_frame, minsize=320)
        self._set_text(self.detail, 'I have no problems to explain yet.\n\nWhen something happens, I will tell you what it means and what to do next in everyday language.')

        log_toolbar = tk.Frame(live, bg=PANEL)
        log_toolbar.pack(fill='x', padx=14, pady=10)
        self.log_path = self.label(log_toolbar, 'Waiting for a native log.', MUTED, 9, anchor='w', width=65)
        self.log_path.pack(side='left', fill='x', expand=True)
        ttk.Button(log_toolbar, text='Import this log', command=self.import_log).pack(side='right')
        log_frame = tk.Frame(live, bg=FIELD)
        log_frame.pack(fill='both', expand=True, padx=14, pady=(0, 14))
        self.log_text = self._text(log_frame)
        self._set_text(self.log_text, 'Native output appears here while Aetheria runs.\nThe view is bounded; complete original logs remain on disk.')

        footer = tk.Frame(self.window, bg=BG)
        footer.pack(fill='x', padx=24, pady=10)
        self.label(footer, '', MUTED, 9, textvariable=self.status).pack(side='left')
        ttk.Button(footer, text='Choose Godot…', command=self.choose_engine).pack(side='right')
        self.label(footer, 'Minimize keeps watching · Close exits Sentinel', MUTED, 9).pack(side='right', padx=12)

    def _card(self, parent, heading, value, hint, column):
        parent.columnconfigure(column, weight=1, uniform='cards')
        frame = tk.Frame(parent, bg=PANEL, padx=15, pady=12)
        frame.grid(row=0, column=column, sticky='nsew', padx=(0 if column == 0 else 8, 0))
        self.label(frame, heading, MUTED, 9, True).pack(anchor='w')
        title = self.label(frame, value, TEXT, 16, True)
        title.pack(anchor='w', pady=(4, 2))
        detail = self.label(frame, hint, MUTED, 9, anchor='w')
        detail.pack(anchor='w')
        return title, detail

    def _text(self, parent):
        scrollbar = ttk.Scrollbar(parent)
        scrollbar.pack(side='right', fill='y')
        text = tk.Text(parent, bg=FIELD, fg=TEXT, insertbackground=BLUE, selectbackground='#254467', wrap='word',
                       font=('Consolas', 10), relief='flat', padx=13, pady=12, yscrollcommand=scrollbar.set)
        text.pack(fill='both', expand=True)
        scrollbar.configure(command=text.yview)
        return text

    def _set_text(self, widget, value, bottom=False):
        widget.configure(state='normal')
        widget.delete('1.0', 'end')
        widget.insert('1.0', value)
        widget.configure(state='disabled')
        if bottom:
            widget.see('end')

    def apply(self, snapshot):
        self.state = snapshot
        active, count = snapshot['active'], snapshot['open_count']
        self.game_card.configure(text='Running' if active else 'Not running', fg=GREEN if active else TEXT)
        self.game_hint.configure(text='I am watching while you play.' if active else 'Watching for the next launch.')
        self.incident_card.configure(text=str(count), fg=AMBER if count else GREEN)
        self.incident_hint.configure(text='Select Incidents for an explanation.' if count else 'No unresolved issues recorded.')
        last = snapshot.get('last_exit')
        if last:
            self.exit_card.configure(text=last['status'], fg=GREEN if last['clean'] else AMBER)
            self.exit_hint.configure(text='The game closed normally.' if last['clean'] else 'The game stopped; the cause needs checking.')
        attention = bool(count or (last and not last['clean']))
        self.badge.configure(text='●  ATTENTION' if attention else '●  GAME RUNNING' if active else '●  WATCHING', fg=AMBER if attention else GREEN)
        latest = next((row for row in snapshot['incidents'] if not row.get('cleared')), None)
        self.greeting.configure(text='A fix has been checked.' if latest and verified_resolution(latest) else 'Let me explain what I found.' if count else 'Watching Aetheria.' if active else 'Standing by.')
        preview = '\n\n'.join(report_explanation(latest).split('\n\n')[:2]) if latest else ''
        if len(preview) > 440:
            preview = preview[:440].rsplit(' ', 1)[0] + '…'
        self.explanation.configure(text=(preview + '\n\nChoose Explain latest to read more or talk it through with me.') if latest else 'I am watching while you play. I will stay here if the game stops.' if active else 'Start Aetheria whenever you are ready. I will keep watch, even when Godot is closed.')
        self.launch_button.configure(state='disabled' if active else 'normal')
        self.status.set('Monitor issue: ' + snapshot['error'][:100] if snapshot.get('error') else snapshot.get('notice') or 'Monitoring locally · AI requests only when you ask in Explain & chat')
        self.clear_button.configure(state='normal' if any(not row.get('cleared') for row in snapshot['incidents']) else 'disabled')
        activity_signature = tuple((e['time'], e['message']) for e in snapshot['activity'])
        if activity_signature != self.activity_signature:
            self.activity_signature = activity_signature
            self.activity.delete(*self.activity.get_children())
            for entry in reversed(snapshot['activity'][-100:]):
                self.activity.insert('', 'end', values=(entry['time'][11:19] + ' UTC', entry['level'], entry['message']))
        self._show_incidents()
        log_signature = (snapshot.get('log_path'), tuple(snapshot['log']))
        if log_signature != self.log_signature:
            self.log_signature = log_signature
            self.log_path.configure(text=snapshot.get('log_path') or 'Waiting for a native log.')
            self._set_text(self.log_text, '\n'.join(snapshot['log']) if snapshot['log'] else 'Waiting for Aetheria output…', bottom=True)

    def _show_incidents(self, force=False):
        rows = [r for r in self.state['incidents'] if self.filter.get() != 'Unresolved' or (not r['resolved'] and not r.get('cleared'))]
        signature = tuple((r['data']['id'], r['data']['count'], r['resolved'], r.get('cleared'), r.get('signature')) for r in rows)
        if not force and signature == self.tree_signature:
            return
        self.tree_signature = signature
        chosen = self.selected
        self.incidents.delete(*self.incidents.get_children())
        for row in rows:
            data = row['data']
            prefix = 'Cleared · ' if row.get('cleared') else '✓ ' if row['resolved'] else ''
            self.incidents.insert('', 'end', iid=data['id'], values=(incident_area(data), data['count'], prefix + incident_title(data)))
        if rows:
            identity = chosen if chosen in self.incidents.get_children() else rows[0]['data']['id']
            self.incidents.selection_set(identity)
            self.select_incident()
        else:
            self.selected = None
            self._set_text(self.detail, '0 results.\n\nI will keep watching for new incidents. Choose “All retained” to inspect cleared or resolved history.')

    def clear_results(self):
        observed = [{'id': row['data']['id'], 'occurrence_count': row['data']['count'],
                     'last_seen': row['data']['last_seen']}
                    for row in self.state['incidents'] if not row.get('cleared')]
        if not observed:
            return
        self.filter.set('Unresolved')
        self.request('clear', observed)

    def _selected_row(self):
        return next((r for r in self.state['incidents'] if r['data']['id'] == self.selected), None)

    def _report_for_chat(self):
        return self._selected_row() or next((r for r in self.state['incidents'] if not r['resolved'] and not r.get('cleared')), None)

    def explain_report(self):
        self.ai_panel.set_report(self._report_for_chat())
        self.tabs.select(3)

    def explain_latest(self):
        latest = next((row for row in self.state['incidents'] if not row.get('cleared')), None)
        if latest:
            self.selected = latest['data']['id']
            self.filter.set('All retained')
            self._show_incidents(force=True)
        else:
            self.selected = None
        self.explain_report()

    def select_incident(self, _event=None):
        selected = self.incidents.selection()
        if not selected:
            return
        self.selected = selected[0]
        self.render_detail()

    def render_detail(self):
        row = self._selected_row()
        if row:
            self.detail.configure(font=('Consolas', 10) if self.technical.get() else ('Segoe UI', 11))
            self._set_text(self.detail, adc.compact(row['data'], row['path']) if self.technical.get() else report_explanation(row))

    def _copy(self, text):
        self.window.clipboard_clear()
        self.window.clipboard_append(text)
        self.status.set('Compact report copied. Paste it into your Codex chat.')

    def copy_latest(self):
        row = next((row for row in self.state['incidents'] if not row.get('cleared')), None)
        self._copy(adc.compact(row['data'], row['path']) if row else 'No ADC incidents recorded.')

    def copy_selected(self):
        row = self._selected_row()
        if row:
            self._copy(adc.compact(row['data'], row['path']))
        else:
            self.status.set('Select an incident first.')

    def open_reports(self):
        self.monitor.root.mkdir(parents=True, exist_ok=True)
        os.startfile(self.monitor.root)

    def open_detail(self):
        row = self._selected_row()
        if row and Path(row['path']).suffix == '.json' and Path(row['path']).is_file():
            os.startfile(row['path'])

    def request(self, action, value=None):
        try:
            self.monitor.enqueue(action, value)
            self.status.set('Working locally…')
        except queue.Full:
            self.status.set('A request is already queued. Try again shortly.')

    def launch(self):
        if not self.monitor.engine or not Path(self.monitor.engine).is_file():
            self.choose_engine()
        if self.monitor.engine:
            self.request('launch', self.monitor.engine)

    def choose_engine(self):
        selected = filedialog.askopenfilename(title='Choose your installed Godot executable', filetypes=[('Godot executable', '*.exe'), ('All files', '*')])
        if selected:
            self.monitor.engine = selected
            self.settings['godot'] = selected
            try:
                adc.atomic(self.settings_path, self.settings)
            except OSError as error:
                self.status.set('Could not save engine preference: ' + str(error))

    def import_log(self):
        path = self.state.get('log_path')
        if path and Path(path).is_file():
            self.request('import', path)
        else:
            self.status.set('There is no native log to import yet.')

    def background(self):
        self.status.set('Sentinel continues watching while minimized. Restore it from the taskbar.')
        self.window.iconify()

    def _tick(self):
        if self.closed:
            return
        newest = None
        while True:
            try:
                newest = self.monitor.notifications.get_nowait()
            except queue.Empty:
                break
        if newest:
            self.apply(newest)
        self.window.after(250, self._tick)

    def close(self):
        self.closed = True
        self.ai_panel.close()
        self.monitor.close()
        self.window.destroy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--background', action='store_true', help='Start minimized; keep monitoring in the taskbar')
    parser.add_argument('--roadmap', action='store_true', help='Open the Roadmap tab')
    args = parser.parse_args()
    root = (args.root or adc.default_root()).resolve()
    guard = SingleInstance(hashlib.sha256(str(root).lower().encode()).hexdigest()[:24])
    if guard.exists:
        if sys.platform == 'win32':
            user = ctypes.WinDLL('user32', use_last_error=True)
            user.FindWindowW.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p]
            user.FindWindowW.restype = ctypes.c_void_p
            user.ShowWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
            user.SetForegroundWindow.argtypes = [ctypes.c_void_p]
            handle = user.FindWindowW(None, 'Aetheria Sentinel')
            if handle:
                user.ShowWindow(handle, 9)
                user.SetForegroundWindow(handle)
        guard.close()
        return 0
    try:
        window = tk.Tk()
        app = SentinelApp(window, Monitor(root))
        if args.roadmap:
            app.tabs.select(app.roadmap)
        if args.background:
            window.after(100, app.background)
        window.mainloop()
        return 0
    finally:
        guard.close()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        try:
            adc.atomic(adc.default_root() / 'companion/startup-error.txt', f'{type(error).__name__}: {error}\n')
            messagebox.showerror('Aetheria Sentinel', 'Sentinel could not start:\n' + str(error))
        except Exception:
            pass
        raise
