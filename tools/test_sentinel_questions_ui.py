"""Real Tk question-flow regressions; isolated state and a non-inference controller."""
from pathlib import Path
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch
import threading

import adc
from sentinel import SentinelApp
from sentinel_monitor import Monitor


class QuestionController:
    def __init__(self, panel):
        self.panel=panel
        self.server=None
        self.jobs={}
        self.connected=0
        self.launched=[]
        self.failure=None
    def connect(self):
        self.connected+=1
        if self.failure: raise RuntimeError(self.failure)
        self.server=object()
        return {'account':{'type':'chatgpt'},'models':[{
            'id':'small','model':'gpt-6-luna','supportedReasoningEfforts':[{'reasoningEffort':'low'}]}]}
    def launch(self,task,*,approved=False):
        self.launched.append((task,approved))
        job={'thread':'q1','turn':'t1','task':task,'status':'running','finished':False}
        self.jobs['q1']=job
        self.panel.emit({'type':'job','thread':'q1','status':'running'})
        return job
    def close(self): pass


class QuestionUITests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.window=tk.Tk()
        self.window.report_callback_exception=lambda *args: self.fail(str(args))
        self.app=SentinelApp(self.window,Monitor(Path(self.temp.name),discover=False),start=False)
        self.panel=self.app.development
        self.panel.controller.close()
        self.fake=QuestionController(self.panel)
        self.panel.controller=self.fake
        self.app.tabs.select(self.panel)
        self.window.geometry('920x560')
        self.window.update()
    def tearDown(self):
        self.app.close()
        self.temp.cleanup()
    def pump(self,until,timeout=12):
        deadline=time.monotonic()+timeout
        while not until() and time.monotonic()<deadline:
            self.window.update()
            time.sleep(.02)
        self.window.update()
        self.assertTrue(until())
    def ask(self):
        self.panel.request_box.insert('1.0','How does fishing work?')
        self.panel.ask_button.invoke()
        self.pump(lambda: bool(self.fake.launched))

    def test_one_click_connects_prepares_and_starts_readonly_question(self):
        self.ask()
        task,approved=self.fake.launched[0]
        self.assertEqual(self.fake.connected,1)
        self.assertEqual(task['mode'],'question')
        self.assertIsNone(task['validation'])
        self.assertTrue(approved)
        self.assertTrue(self.panel.ask_button.instate(['disabled']))
        self.assertTrue(self.panel.answer_box.winfo_ismapped())
        self.assertFalse(self.panel.model_box.winfo_ismapped())
        self.assertGreater(self.panel.answer_box.winfo_height(),60)
        bottom=self.panel.ask_button.winfo_rooty()+self.panel.ask_button.winfo_height()
        self.assertLessEqual(bottom,self.window.winfo_rooty()+self.window.winfo_height())

    def test_connection_error_is_visible_and_question_can_be_retried(self):
        self.fake.failure='Codex could not connect. Check sign-in.'
        self.panel.request_box.insert('1.0','How does fishing work?')
        self.panel.ask_button.invoke()
        self.pump(lambda: 'Check sign-in' in self.panel.answer_box.get('1.0','end'))
        self.assertFalse(self.panel.ask_button.instate(['disabled']))
        self.assertFalse(self.fake.launched)

    def test_streaming_answer_and_completion_stay_visible_after_index_refresh(self):
        self.ask()
        report={'tokens':50,'token_budget':12000,'commands':0,'files':[],'repeated_operations':0,'warnings':[]}
        self.panel.emit({'type':'progress','thread':'q1','report':report,'answer':'Fishing checks'})
        self.pump(lambda:'Fishing checks' in self.panel.answer_box.get('1.0','end'))
        self.panel.emit({'type':'finished','thread':'q1','status':'completed','body':{'answer':'Fishing checks your equipment.','error':'','report':report}})
        self.pump(lambda:not self.panel.ask_button.instate(['disabled']))
        self.panel.emit({'type':'indexed','value':{'files':10,'read':0,'updated':0,'removed':0}})
        self.window.update()
        self.assertIn('Fishing checks your equipment.',self.panel.answer_box.get('1.0','end'))
        self.assertIn('Answer',self.panel.status.get())

    def test_blank_question_and_repeated_click_cannot_launch_hidden_work(self):
        self.panel.ask_button.invoke()
        self.assertIn('Type',self.panel.status.get())
        self.assertFalse(self.fake.launched)
        self.ask()
        self.panel.ask_button.invoke()
        self.assertEqual(len(self.fake.launched),1)

    def test_stop_during_connection_cancels_before_model_request(self):
        connecting=threading.Event()
        release=threading.Event()
        connect=self.fake.connect
        def delayed_connect():
            connecting.set()
            release.wait(5)
            return connect()
        self.fake.connect=delayed_connect
        self.panel.request_box.insert('1.0','How does fishing work?')
        self.panel.ask_button.invoke()
        self.pump(connecting.is_set)
        self.panel.stop()
        release.set()
        self.pump(lambda:not self.panel.ask_button.instate(['disabled']))
        self.assertFalse(self.fake.launched)
        self.assertIn('cancelled',self.panel.answer_box.get('1.0','end').lower())

    def test_shipped_budget_covers_measured_codex_startup_context(self):
        from sentinel_assistant import Governor
        self.ask()
        task=self.fake.launched[0][0]
        governor=Governor(tokens=task['tokens'],seconds=task['seconds'])
        reason=governor.observe({'method':'thread/tokenUsage/updated','params':{'tokenUsage':{'total':{'totalTokens':14496}}}})
        self.assertIsNone(reason,'The old shipped limit stopped even a one-line answer at startup.')


if __name__=='__main__': unittest.main(verbosity=2)
