"""Real Tk interactions with an isolated deployment controller; never publish."""
import threading
import time
import tkinter as tk
from pathlib import Path
import tempfile
import gc
import unittest
from unittest.mock import patch

from sentinel_deploy_panel import DeploymentPanel
from sentinel import SentinelApp
from sentinel_monitor import Monitor


class FakeController:
    def __init__(self):
        self.calls=[]
        self.release='old-release'
        self.gate=None
        self.fail=False
        self.eligible=True
    def preview(self,engine=None):
        return {'eligible':self.eligible,'engine':engine,'mode':'beta-live',
                'target':{'world_host':'play.example','world_port':24567,'world_id':'aetheria'},
                'current_release':self.release,
                'source':{'branch':'codex/test','commit':'abc123','changed_files':3,'summary':['game/map.tscn']},
                'prerequisites':[{'name':'Configured live server','ok':self.eligible,'detail':'Not configured' if not self.eligible else 'Ready'}]}
    def status(self):
        return {'ok':True,'state':'running','release_id':self.release,'message':'Observed running server'}
    def update(self,engine,emit):
        self.calls.append((engine,threading.get_ident()))
        emit('Building matching client and server')
        if self.gate:self.gate.wait(2)
        if self.fail:return {'ok':False,'returncode':1,'message':'Upload failed','release_id':self.release}
        self.release='new-release'
        return {'ok':True,'returncode':0,'message':'Verified running release','release_id':self.release,'status':self.status()}


class DeploymentPanelTests(unittest.TestCase):
    def setUp(self):
        self.window=tk.Tk()
        self.errors=[]
        self.window.report_callback_exception=lambda *args:self.errors.append(str(args))
        self.controller=FakeController()
        self.panel=DeploymentPanel(self.window,controller=self.controller,engine_provider=lambda:'godot.exe',start=False)
        self.panel.pack(fill='both',expand=True)
        self.window.geometry('920x560')
        self.window.update()
    def tearDown(self):
        if self.controller.gate:self.controller.gate.set()
        self.wait(lambda:not self.panel.busy)
        self.panel.close()
        self.window.destroy()
    def wait(self,condition,seconds=3):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            self.window.update()
            if condition():return True
            time.sleep(.01)
        return False
    def test_refresh_observes_without_deploying(self):
        self.panel.refresh()
        self.assertTrue(self.wait(lambda:not self.panel.busy))
        self.assertIn('old-release',self.panel.release.get())
        self.assertIn('play.example',self.panel.target.get())
        self.assertIn('3',self.panel.source.get())
        self.assertEqual(self.controller.calls,[])
    def test_decline_has_no_live_side_effect(self):
        with patch('sentinel_deploy_panel.messagebox.askyesno',return_value=False) as confirm:
            self.panel.request_update()
            self.assertTrue(self.wait(lambda:not self.panel.busy))
        self.assertTrue(confirm.called)
        self.assertEqual(self.controller.calls,[])
        self.assertIn('canceled',self.panel.status.get().lower())
    def test_confirm_runs_off_ui_thread_and_shows_observed_release(self):
        main=threading.get_ident()
        with patch('sentinel_deploy_panel.messagebox.askyesno',return_value=True) as confirm:
            self.panel.request_update()
            self.assertTrue(self.wait(lambda:bool(self.controller.calls) and not self.panel.busy))
        self.assertNotEqual(self.controller.calls[0][1],main)
        self.assertIn('uncommitted',confirm.call_args.args[1].lower())
        self.assertIn('new-release',self.panel.release.get())
        self.assertIn('complete',self.panel.status.get().lower())
        self.assertIn('Building matching',self.panel.log.get('1.0','end'))
        self.assertFalse(self.errors)
    def test_busy_update_keeps_tk_alive_rejects_duplicate_and_blocks_close(self):
        self.controller.gate=threading.Event()
        heartbeat=[]
        with patch('sentinel_deploy_panel.messagebox.askyesno',return_value=True):
            self.panel.request_update()
            self.assertTrue(self.wait(lambda:bool(self.controller.calls)))
            self.window.after(1,lambda:heartbeat.append(True))
            self.assertTrue(self.wait(lambda:bool(heartbeat)))
            self.panel.request_update()
            self.assertFalse(self.panel.close())
            self.assertEqual(len(self.controller.calls),1)
            self.controller.gate.set()
            self.assertTrue(self.wait(lambda:not self.panel.busy))
    def test_failed_upload_never_reports_success_or_auto_retries(self):
        self.controller.fail=True
        with patch('sentinel_deploy_panel.messagebox.askyesno',return_value=True):
            self.panel.request_update()
            self.assertTrue(self.wait(lambda:bool(self.controller.calls) and not self.panel.busy))
        self.assertIn('failed',self.panel.status.get().lower())
        self.assertIn('old-release',self.panel.release.get())
        self.assertEqual(len(self.controller.calls),1)
    def test_missing_configuration_does_not_offer_publish_confirmation(self):
        self.controller.eligible=False
        with patch('sentinel_deploy_panel.messagebox.askyesno') as confirm:
            self.panel.request_update()
            self.assertTrue(self.wait(lambda:not self.panel.busy))
        confirm.assert_not_called()
        self.assertEqual(self.controller.calls,[])
        self.assertIn('Not configured',self.panel.status.get())


class AppIntegrationTests(unittest.TestCase):
    def test_live_tab_preserves_existing_views_and_blocks_close_during_update(self):
        with tempfile.TemporaryDirectory() as directory:
            window=tk.Tk()
            errors=[]
            window.report_callback_exception=lambda *args:errors.append(str(args))
            app=SentinelApp(window,Monitor(Path(directory),discover=False),start=False)
            try:
                labels=[app.tabs.tab(tab,'text') for tab in app.tabs.tabs()]
                self.assertEqual(labels,['Companion','Incidents','Live log','Explain & chat','Roadmap','Development assistant','Live server'])
                app.tabs.select(app.live_server)
                window.geometry('920x560')
                window.update()
                panel=app.live_server
                self.assertGreater(panel.log.winfo_height(),60)
                self.assertTrue(panel.update_button.winfo_ismapped())
                self.assertLessEqual(panel.update_button.winfo_rootx()+panel.update_button.winfo_width(),window.winfo_rootx()+window.winfo_width())
                self.assertFalse(panel.busy)
                panel.busy=True
                app.close()
                self.assertFalse(app.closed)
                self.assertTrue(window.winfo_exists())
                panel.busy=False
                app.tabs.select(0)
                window.update()
                self.assertTrue(app.launch_button.winfo_ismapped())
                self.assertFalse(errors)
            finally:
                if hasattr(app,'live_server'):app.live_server.busy=False
                app.close()
            # Collect destroyed app widgets here on Tk's thread before a later
            # test starts worker threads that could trigger cyclic collection.
            del app,window,panel
            gc.collect()


if __name__=='__main__':unittest.main(verbosity=2)
