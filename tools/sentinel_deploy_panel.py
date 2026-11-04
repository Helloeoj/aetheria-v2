"""Manual live release controls; Tk stays on its main thread."""
from __future__ import annotations
import os
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import ttk, messagebox

PANEL, FIELD, TEXT, MUTED = '#121d2d', '#0e1725', '#e7eef8', '#94a7c0'


class DeploymentPanel(tk.Frame):
    def __init__(self,parent,repo=None,*,controller=None,engine_provider=None,start=True):
        super().__init__(parent,bg=PANEL)
        if controller is None:
            from sentinel_deploy import DeploymentController
            controller=DeploymentController(Path(repo),Path(os.environ['LOCALAPPDATA'])/'Aetheria/online')
        self.controller=controller
        self.engine_provider=engine_provider or (lambda:None)
        self.events=queue.Queue(maxsize=256)
        self.busy=False
        self.closed=False
        self.log_path=None
        self.status=tk.StringVar(value='Refresh to inspect the installed live release.')
        self.target=tk.StringVar(value='Configured live beta on this PC')
        self.release=tk.StringVar(value='Not checked')
        self.source=tk.StringVar(value='Saved local project files, including uncommitted changes')
        self._build()
        self.timer=self.after(75,self._drain)
        if start:self.after_idle(self.refresh)

    def label(self,parent,**kwargs):
        label=tk.Label(parent,bg=PANEL,fg=TEXT,anchor='w',justify='left',**kwargs)
        label.bind('<Configure>',lambda event:label.configure(wraplength=max(60,event.width-5)))
        return label

    def _build(self):
        header=tk.Frame(self,bg=PANEL)
        header.pack(fill='x',padx=20,pady=(16,8))
        self.label(header,text='Live server updates',font=('Segoe UI Semibold',17)).pack(fill='x')
        self.label(header,text='Build and publish the matching game update, save players, then restart the live world.').pack(fill='x',pady=(4,8))
        for name,variable in [('Target',self.target),('Release',self.release),('Source',self.source)]:
            row=tk.Frame(header,bg=PANEL)
            row.pack(fill='x',pady=2)
            self.label(row,text=name,width=9).pack(side='left',anchor='n')
            self.label(row,textvariable=variable).pack(side='left',fill='x',expand=True)
        actions=tk.Frame(self,bg=PANEL)
        actions.pack(fill='x',padx=20,pady=8)
        self.update_button=ttk.Button(actions,text='Push live update',style='Primary.TButton',command=self.request_update)
        self.update_button.pack(side='left',padx=(0,8))
        self.refresh_button=ttk.Button(actions,text='Refresh status',command=self.refresh)
        self.refresh_button.pack(side='left',padx=(0,8))
        self.log_button=ttk.Button(actions,text='Open update log',command=self.open_log,state='disabled')
        self.log_button.pack(side='left')
        self.progress=ttk.Progressbar(actions,mode='indeterminate',length=130)
        self.progress.pack(side='right')
        self.label(self,textvariable=self.status).pack(fill='x',padx=20,pady=(0,6))
        box=tk.Frame(self,bg=FIELD)
        box.pack(fill='both',expand=True,padx=20,pady=(0,12))
        self.log=tk.Text(box,bg=FIELD,fg=TEXT,insertbackground=TEXT,wrap='word',state='disabled',height=6,borderwidth=0,font=('Consolas',10))
        scroll=ttk.Scrollbar(box,command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right',fill='y')
        self.log.pack(side='left',fill='both',expand=True)

    def _post(self,kind,value):
        # Drop oldest progress under a burst, never block the release process.
        while True:
            try:self.events.put_nowait((kind,value));return
            except queue.Full:
                try:self.events.get_nowait()
                except queue.Empty:pass

    def _begin(self,kind,operation):
        if self.busy or self.closed:return
        self.busy=True
        self.update_button.configure(state='disabled')
        self.refresh_button.configure(state='disabled')
        self.progress.start(15)
        def work():
            try:self._post(kind,operation())
            except Exception as error:self._post('error',str(error)[:2000])
        threading.Thread(target=work,name='Sentinel-live-'+kind,daemon=True).start()

    def _idle(self):
        self.busy=False
        self.progress.stop()
        self.update_button.configure(state='normal')
        self.refresh_button.configure(state='normal')

    def _append(self,line):
        self.log.configure(state='normal')
        self.log.insert('end',str(line)[:4096].rstrip()+'\n')
        count=int(self.log.index('end-1c').split('.')[0])
        if count>500:self.log.delete('1.0',f'{count-500}.0')
        self.log.see('end')
        self.log.configure(state='disabled')

    def _show_preview(self,preview):
        target=preview.get('target',{})
        self.target.set(f"{target.get('world_host','Not configured')}:{target.get('world_port','')} · {target.get('world_id','')}")
        self.release.set(preview.get('current_release') or 'No installed release')
        source=preview.get('source',{})
        self.source.set(f"Saved local files · {source.get('branch','unknown branch')} · {source.get('commit','')[:12]} · {source.get('changed_files',0)} changed files")

    def refresh(self):
        if self.busy or self.closed:return
        engine=self.engine_provider()
        self.status.set('Checking the installed release and running process…')
        self._begin('snapshot',lambda:(self.controller.preview(engine),self.controller.status()))

    def request_update(self):
        if self.busy or self.closed:return
        engine=self.engine_provider()
        self.status.set('Preparing the update review…')
        self._begin('review',lambda:self.controller.preview(engine))

    def _review(self,preview):
        self._show_preview(preview)
        if not preview.get('eligible'):
            reasons=[str(item.get('detail') or item.get('name')) for item in preview.get('prerequisites',[]) if not item.get('ok')]
            self.status.set('Cannot update: '+('; '.join(reasons) or 'Live hosting is not configured.'))
            return
        source=preview.get('source',{})
        body=(f"Publish saved project files to {self.target.get()}?\n\n"
              f"Current release: {self.release.get()}\n"
              f"Source: {source.get('branch','local project')} ({source.get('commit','')[:12]})\n"
              f"Uncommitted changes are included ({source.get('changed_files',0)} changed files).\n\n"
              "This publishes a matching client/server update, saves players, creates a recovery backup and restarts the live world. Players may need to reconnect.\n\n"
              "Keep Sentinel open until the result is verified. Continue?")
        if not messagebox.askyesno('Push live update',body,parent=self.winfo_toplevel(),default='no'):
            self.status.set('Update canceled. No live changes made.')
            return
        self.status.set('Live update in progress. Keep Sentinel open…')
        self._append('Starting the existing live release workflow from saved local project files.')
        self._begin('updated',lambda:self.controller.update(preview.get('engine'),lambda line:self._post('line',line)))

    def _drain(self):
        if self.closed:return
        for _ in range(100):
            try:kind,value=self.events.get_nowait()
            except queue.Empty:break
            if kind=='line':self._append(value);continue
            self._idle()
            if kind=='snapshot':
                preview,state=value
                self._show_preview(preview)
                if state.get('release_id'):self.release.set(state['release_id'])
                self.status.set(state.get('message') or state.get('state','Unknown server state'))
            elif kind=='review':self._review(value)
            elif kind=='updated':
                if value.get('release_id'):self.release.set(value['release_id'])
                self.log_path=value.get('log_path')
                self.log_button.configure(state='normal' if self.log_path else 'disabled')
                if value.get('ok') is True and value.get('returncode')==0:
                    self.status.set('Live update complete · '+str(value.get('release_id','')))
                else:self.status.set('Live update failed: '+str(value.get('message','Running release was not verified.')))
                self._append(value.get('message',self.status.get()))
            else:
                self.status.set('Live update/status failed: '+str(value))
                self._append(value)
        self.timer=self.after(75,self._drain)

    def open_log(self):
        if self.log_path and Path(self.log_path).is_file():os.startfile(self.log_path)

    def close(self):
        if self.busy:
            self.status.set('Wait for the current server action to finish before closing Sentinel.')
            return False
        self.closed=True
        if self.timer:
            try:self.after_cancel(self.timer)
            except tk.TclError:pass
            self.timer=None
        return True
