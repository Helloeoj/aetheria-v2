"""Native Sentinel version of the original interactive gameplay brainstorm board."""
from __future__ import annotations

import os
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from sentinel_roadmap import (RoadmapStore, LOOPS, CORE, DEPTH, TASKS, LOOP_TASKS,
                              ADVENTURE, BUILD, CONCLUSIONS)

PANEL, FIELD, TEXT, MUTED, BLUE, GREEN = '#121d2d', '#0e1725', '#e7eef8', '#94a7c0', '#69bcff', '#71dcc0'


class ScrollPage(tk.Frame):
    def __init__(self, parent):
        super().__init__(parent, bg=PANEL)
        self.canvas = tk.Canvas(self, bg=PANEL, bd=0, highlightthickness=0)
        scroll = ttk.Scrollbar(self, orient='vertical', command=self.canvas.yview)
        scroll.pack(side='right', fill='y')
        self.canvas.pack(fill='both', expand=True)
        self.canvas.configure(yscrollcommand=scroll.set)
        self.body = tk.Frame(self.canvas, bg=PANEL, padx=18, pady=16)
        self.item = self.canvas.create_window(0, 0, anchor='nw', window=self.body)
        self.canvas.bind('<Configure>', lambda e: self.canvas.itemconfigure(self.item, width=e.width))
        self.body.bind('<Configure>', lambda _: self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.tag = f'RoadmapWheel{id(self)}'
        self.bind_class(self.tag, '<MouseWheel>', self._wheel)
        self.bind('<Destroy>', self._destroy, add='+')

    def _wheel(self, event):
        if self.canvas.bbox('all') and self.body.winfo_height() > self.canvas.winfo_height():
            self.canvas.yview_scroll(-int(event.delta / 120) or (-1 if event.delta > 0 else 1), 'units')
        return 'break'

    def wire(self, widget=None):
        widget = widget or self
        if self.tag not in widget.bindtags():
            widget.bindtags((widget.bindtags()[0], self.tag) + widget.bindtags()[1:])
        for child in widget.winfo_children():
            self.wire(child)

    def _destroy(self, event):
        if event.widget is self:
            self.unbind_class(self.tag, '<MouseWheel>')


class RoadmapPanel(tk.Frame):
    def __init__(self, parent, state_path):
        super().__init__(parent, bg=PANEL)
        self.store = RoadmapStore(state_path)
        self.variables = {key: tk.BooleanVar(value=self.store.done(key)) for key in TASKS}
        self.loop_key = self.store.state.get('loop', 'expedition')
        if self.loop_key not in LOOPS:
            self.loop_key = 'expedition'
        self.count_labels = []
        self.checkboxes = []
        self.loop_buttons = {}
        self.status = tk.StringVar(value=self.store.error or 'Check off completed work. Each change is saved automatically; uncheck to reopen.')
        self._build()
        self.select_loop(self.loop_key, save=False)
        view = self.store.state.get('view', 'loops')
        self.views.select({'loops': 0, 'mechanics': 1, 'next': 2}.get(view, 0))
        self.views.bind('<<NotebookTabChanged>>', self._view_changed)
        self.refresh_progress()

    def label(self, parent, text, *, muted=False, size=10, bold=False, **kwargs):
        label = tk.Label(parent, text=text, fg=MUTED if muted else TEXT, bg=parent.cget('bg'),
                         font=('Segoe UI Semibold' if bold else 'Segoe UI', size), anchor='w', justify='left', **kwargs)
        label.bind('<Configure>', lambda e: label.configure(wraplength=max(40, e.width - 2)))
        return label

    def heading(self, parent, text):
        self.label(parent, text, size=14, bold=True).pack(fill='x', pady=(10, 8))

    def detail(self, parent, name, value):
        row = tk.Frame(parent, bg=PANEL)
        row.pack(fill='x', pady=5)
        row.columnconfigure(1, weight=1)
        self.label(row, name, muted=True, width=17).grid(row=0, column=0, sticky='nw', padx=(0, 10))
        self.label(row, value).grid(row=0, column=1, sticky='ew')

    def _build(self):
        top = tk.Frame(self, bg=PANEL)
        top.pack(fill='x', padx=18, pady=(14, 5))
        top.columnconfigure(0, weight=1)
        self.label(top, 'Aetheria · gameplay direction', size=17, bold=True).grid(row=0, column=0, sticky='ew')
        ttk.Button(top, text='Full brainstorm', command=self.open_notes).grid(row=0, column=1, padx=(14, 0))
        self.label(top, 'Prepare in town → venture out → return stronger').grid(row=1, column=0, columnspan=2, sticky='ew', pady=(4, 0))
        self.label(top, 'Starting snapshot · Oct 19, 2026 · Proposed direction, not a playtest', muted=True, size=9).grid(row=2, column=0, columnspan=2, sticky='ew', pady=(4, 0))
        progress_row = tk.Frame(self, bg=PANEL)
        progress_row.pack(fill='x', padx=18, pady=(5, 2))
        self.progress_label = self.label(progress_row, '', bold=True)
        self.progress_label.pack(side='left')
        self.progress = ttk.Progressbar(progress_row, maximum=len(TASKS), length=180)
        self.progress.pack(side='left', padx=16)
        self.label(progress_row, 'Manual checklist · no automatic code verification', muted=True, size=9).pack(side='left')
        status = self.label(self, '', muted=True, size=9, textvariable=self.status)
        status.pack(fill='x', padx=18, pady=(3, 7))
        self.views = ttk.Notebook(self)
        self.views.pack(fill='both', expand=True, padx=4, pady=(0, 4))
        self.pages = [ScrollPage(self.views) for _ in range(3)]
        for page, name in zip(self.pages, ['Missing loops', 'Core mechanics', 'Build next']):
            self.views.add(page, text=name)
        self._build_loops(self.pages[0].body)
        self._build_mechanics(self.pages[1].body)
        self._build_next(self.pages[2].body)
        for page in self.pages:
            page.wire()

    def _build_loops(self, body):
        self.label(body, '✓ Tick combat + styles     ✓ Loot + equipment     ✓ Skills + spell unlocks     ✓ Terrain + pursuit + leashing', muted=True, size=9).pack(fill='x', pady=(0, 14))
        controls = tk.Frame(body, bg=PANEL)
        controls.pack(fill='x', pady=(0, 14))
        for i, (key, title) in enumerate(zip(LOOPS, ['Expedition · first', 'Resupply · first', 'Production', 'Discovery', 'Mastery', 'Collection'])):
            button = ttk.Button(controls, text=title, command=lambda key=key: self.select_loop(key))
            button.grid(row=i // 3, column=i % 3, sticky='ew', padx=(0, 7), pady=(0, 7))
            controls.columnconfigure(i % 3, weight=1)
            self.loop_buttons[key] = button
        self.loop_body = tk.Frame(body, bg=PANEL)
        self.loop_body.pack(fill='x')
        ttk.Separator(body).pack(fill='x', pady=16)
        self.label(body, 'Loop = a sequence worth repeating. Mechanic = an action or rule that makes it work.', muted=True, size=9).pack(fill='x')

    def select_loop(self, key, save=True):
        self.loop_key = key
        for widget in self.loop_body.winfo_children():
            widget.destroy()
        # Keep only live summary labels/buttons after rebuilding the selected loop.
        self.count_labels = [(label, ids) for label, ids in self.count_labels if label.winfo_exists()]
        self.checkboxes = [box for box in self.checkboxes if box.winfo_exists()]
        for candidate, button in self.loop_buttons.items():
            button.configure(style='Primary.TButton' if candidate == key else 'TButton')
        data = LOOPS[key]
        self.heading(self.loop_body, data['name'])
        self.label(self.loop_body, data['priority'], muted=True, size=9).pack(fill='x')
        route = tk.Frame(self.loop_body, bg=PANEL)
        route.pack(fill='x', pady=16)
        for i, (name, state, kind) in enumerate(data['steps']):
            col = i % 3
            route.columnconfigure(col, weight=1, uniform='route')
            cell = tk.Frame(route, bg=PANEL)
            cell.grid(row=i // 3, column=col, sticky='nsew', padx=(0, 14), pady=(0, 16))
            tk.Frame(cell, bg=BLUE if kind == 'new' else '#304258', height=2).pack(fill='x', pady=(0, 10))
            self.label(cell, str(i + 1), muted=True, size=9).pack(fill='x')
            self.label(cell, name, bold=True).pack(fill='x', pady=4)
            self.label(cell, state, muted=True, size=9).pack(fill='x')
        self.label(self.loop_body, 'Player decision', bold=True).pack(fill='x')
        self.label(self.loop_body, data['question']).pack(fill='x', pady=(4, 14))
        for name, field in [('Already here', 'exists'), ('Missing link', 'gap'), ('Smallest version', 'minimum')]:
            self.detail(self.loop_body, name, data[field])
        self.heading(self.loop_body, 'Related checklist')
        self.summary(self.loop_body, LOOP_TASKS[key])
        for task in LOOP_TASKS[key]:
            self.task(self.loop_body, task, detail=False)
        self.refresh_progress()
        self.pages[0].wire()
        self.pages[0].canvas.yview_moveto(0)
        if save:
            self.save_view()

    def summary(self, parent, keys):
        label = self.label(parent, '', muted=True, size=9)
        label.pack(fill='x', pady=(0, 8))
        self.count_labels.append((label, keys))

    def task(self, parent, key, detail=True):
        row = tk.Frame(parent, bg=FIELD, padx=12, pady=9)
        row.pack(fill='x', pady=(0, 5))
        row.columnconfigure(1, weight=1)
        checkbox = ttk.Checkbutton(row, variable=self.variables[key], command=lambda: self.toggle(key))
        checkbox.grid(row=0, column=0, sticky='n', padx=(0, 10))
        title = self.label(row, TASKS[key]['title'], bold=True)
        title.grid(row=0, column=1, sticky='ew')
        title.bind('<Button-1>', lambda _: checkbox.invoke())
        if detail:
            self.label(row, TASKS[key]['detail'], muted=True).grid(row=1, column=1, sticky='ew', pady=(3, 0))
        if self.store.error:
            checkbox.configure(state='disabled')
        self.checkboxes.append(checkbox)

    def _build_mechanics(self, body):
        self.heading(body, 'Complete the adventure')
        self.summary(body, [key for key, _, _ in CORE])
        for key, _, _ in CORE:
            self.task(body, key)
        self.heading(body, 'Add depth after the loop works')
        self.summary(body, [key for key, _, _ in DEPTH])
        for key, _, _ in DEPTH:
            self.task(body, key)

    def _build_next(self, body):
        self.heading(body, 'The Roadside Job · first playable adventure')
        self.label(body, 'Proposed 15–25 minute playtest target · existing tavern, road and woodland', muted=True, size=9).pack(fill='x', pady=(0, 12))
        for i, (title, text) in enumerate(ADVENTURE, 1):
            self.label(body, f'{i}. {title}', bold=True).pack(fill='x', pady=(8, 3))
            self.label(body, text).pack(fill='x', padx=(20, 0))
        ttk.Separator(body).pack(fill='x', pady=18)
        self.heading(body, 'Build order')
        for i, (title, subtitle, keys) in enumerate(BUILD, 1):
            self.label(body, f'{i}. {title}', bold=True).pack(fill='x', pady=(10, 5))
            if subtitle:
                self.label(body, subtitle, muted=True).pack(fill='x', pady=(0, 5))
            self.summary(body, keys)
            for key in keys:
                self.task(body, key, detail=False)
        ttk.Separator(body).pack(fill='x', pady=16)
        for name, value in CONCLUSIONS:
            self.detail(body, name, value)

    def toggle(self, key):
        try:
            self.store.set_done(key, self.variables[key].get())
        except OSError as error:
            self.variables[key].set(self.store.done(key))
            self.status.set(f'Not saved; your change was undone. {error}')
            return
        self.status.set(f'Saved · {TASKS[key]["title"]} · {"complete" if self.store.done(key) else "reopened"}')
        self.refresh_progress()

    def refresh_progress(self):
        done, total = self.store.count()
        self.progress_label.configure(text=f'{done} / {total} complete · {round(100 * done / total)}%')
        self.progress.configure(value=done)
        for label, keys in self.count_labels:
            done, total = self.store.count(keys)
            label.configure(text=f'{done} / {total} checked off' + (' · Complete' if done == total else ''))

    def _view_changed(self, _event=None):
        self.save_view()

    def save_view(self):
        view = ['loops', 'mechanics', 'next'][self.views.index(self.views.select())]
        try:
            self.store.set_view(view, self.loop_key)
        except OSError as error:
            self.status.set(f'View preference could not be saved. {error}')

    def open_notes(self):
        path = Path(__file__).resolve().parents[1] / 'godot_client/docs/Roadmap.md'
        try:
            os.startfile(path)
        except OSError as error:
            self.status.set(f'Could not open the full brainstorm: {error}')
