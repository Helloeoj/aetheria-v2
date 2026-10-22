"""Real Tk routing/credit regressions with fake Codex and no inference."""
from pathlib import Path
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch
import threading

from sentinel import SentinelApp
from sentinel_monitor import Monitor


class QuestionController:
    def __init__(self,panel):
        self.panel=panel; self.server=None; self.jobs={}
        self.connected=0; self.launched=[]; self.failure=None
    def connect(self):
        self.connected+=1
        if self.failure: raise RuntimeError(self.failure)
        self.server=object()
        return {'account':{'type':'chatgpt'},'models':[{
            'id':'small','model':'gpt-6-luna','supportedReasoningEfforts':[{'reasoningEffort':'low'}]}],
            'usage':{'balance':'250','ordinary_usage_allowed':True}}
    def launch(self,task,*,approved=False):
        self.launched.append((task,approved))
        job={'thread':'q1','turn':'t1','task':task,'status':'running','finished':False}
        self.jobs['q1']=job
        self.panel.emit({'type':'job','thread':'q1','status':'running'})
        return job
    def close(self): pass


class BrowserController:
    def __init__(self):
        self.started=0
        self.retried=0
        self.commands=[]
    def start(self): self.started+=1
    def retry(self): self.retried+=1
    def command(self,command,**kwargs): self.commands.append((command,kwargs))
    def close(self): pass


class QuestionUITests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.window=tk.Tk()
        self.window.report_callback_exception=lambda *args: self.fail(str(args))
        self.app=SentinelApp(self.window,Monitor(Path(self.temp.name),discover=False),start=False)
        self.panel=self.app.development
        self.panel.controller.close()
        self.fake=QuestionController(self.panel); self.panel.controller=self.fake
        self.app.tabs.select(self.panel); self.window.geometry('920x560'); self.window.update()
    def tearDown(self):
        self.app.close(); self.temp.cleanup()
    def pump(self,until,timeout=12):
        deadline=time.monotonic()+timeout
        while not until() and time.monotonic()<deadline:
            self.window.update(); time.sleep(.02)
        self.window.update(); self.assertTrue(until())
    def prepare(self):
        self.panel.route.set('Codex implementation'); self.panel.switch_route()
        self.panel.credits.set('1')
        self.panel.request_box.insert('1.0','Investigate why fishing freezes.')
        self.panel.ask_button.invoke(); self.pump(lambda:self.panel.task is not None)
    def run(self,result=None):
        # unittest's run is intentionally inherited, use launch_stage below.
        return super().run(result)
    def launch_stage(self):
        self.prepare()
        with patch('sentinel_assistant_panel.messagebox.askyesno',return_value=True):
            self.panel.run_task()
        self.pump(lambda:bool(self.fake.launched))
        self.pump(lambda:self.panel.active_question_thread=='q1')

    def test_default_is_embedded_chatgpt_with_no_codex_connection_or_launch(self):
        self.assertEqual(self.panel.route.get(),'ChatGPT conversation')
        self.assertTrue(self.panel.chat_page.winfo_ismapped())
        self.assertFalse(self.panel.coding_page.winfo_ismapped())
        self.panel.ask_question()
        self.assertEqual(self.fake.connected,0); self.assertFalse(self.fake.launched)
        self.assertIsNone(self.panel.chat_browser)

    def test_prepare_is_local_and_paid_launch_needs_review_with_credit_units(self):
        self.prepare()
        self.assertEqual(self.fake.connected,1); self.assertFalse(self.fake.launched)
        self.assertEqual(self.panel.task['credit_limit_micros'],1000000)
        self.assertIsNone(self.panel.task['tokens'])
        self.assertIn('credit',self.panel.preview.get('1.0','end').lower())
        self.assertIn('250 credits',self.panel.credit_status.get())
        with patch('sentinel_assistant_panel.messagebox.askyesno',return_value=False) as confirm:
            self.panel.run_task()
            self.assertIn('1 Codex credits',confirm.call_args.args[1])
        self.assertFalse(self.fake.launched)
        self.assertGreater(self.panel.preview.winfo_height(),40)

    def test_conversation_handoff_prepares_input_but_cannot_launch_paid_job(self):
        self.panel._chat_event({'type':'handoff','request':'Implement the fishing fix we discussed.'})
        self.window.update()
        self.assertEqual(self.panel.route.get(),'Codex implementation')
        self.assertIn('fishing fix',self.panel.request_box.get('1.0','end'))
        self.assertTrue(self.panel.coding_page.winfo_ismapped())
        self.assertFalse(self.fake.launched); self.assertEqual(self.fake.connected,0)
        self.panel.ask_button.invoke()
        self.assertIn('credit budget',self.panel.status.get())
        self.assertFalse(self.fake.launched)
        self.panel.route.set('ChatGPT conversation'); self.panel.switch_route(); self.window.update()
        self.assertTrue(self.panel.chat_page.winfo_ismapped())

    def test_connection_error_is_visible_and_no_inference_was_started(self):
        self.fake.failure='Codex could not connect. Check sign-in.'
        self.panel.route.set('Codex implementation'); self.panel.switch_route()
        self.panel.credits.set('1'); self.panel.request_box.insert('1.0','Fix fishing.')
        self.panel.ask_button.invoke()
        self.pump(lambda:'Check sign-in' in self.panel.answer_box.get('1.0','end'))
        self.assertFalse(self.panel.ask_button.instate(['disabled'])); self.assertFalse(self.fake.launched)

    def test_streaming_and_credit_report_remain_visible_after_index_refresh(self):
        self.launch_stage()
        report={'tokens':50,'token_budget':None,'credits':.02,'credit_budget':1,
                'credit_source':'server_estimate','commands':0,'files':[],'repeated_operations':0,'warnings':[]}
        self.panel.emit({'type':'progress','thread':'q1','report':report,'answer':'Fishing checks'})
        self.pump(lambda:'Fishing checks' in self.panel.answer_box.get('1.0','end'))
        self.panel.emit({'type':'finished','thread':'q1','status':'completed',
                         'body':{'answer':'Fishing checks your equipment.','error':'','report':report}})
        self.pump(lambda:not self.panel.ask_button.instate(['disabled']))
        self.panel.emit({'type':'indexed','value':{'files':10,'read':0,'updated':0,'removed':0}})
        self.window.update()
        self.assertIn('Fishing checks your equipment.',self.panel.answer_box.get('1.0','end'))
        self.assertIn('0.02 / 1',self.panel.usage.get())

    def test_stop_during_connection_cancels_before_preparing_or_model_request(self):
        connecting=threading.Event(); release=threading.Event(); connect=self.fake.connect
        def delayed():
            connecting.set(); release.wait(5); return connect()
        self.fake.connect=delayed
        self.panel.route.set('Codex implementation'); self.panel.switch_route()
        self.panel.credits.set('1'); self.panel.request_box.insert('1.0','Fix fishing.')
        self.panel.ask_button.invoke(); self.pump(connecting.is_set)
        self.panel.stop(); release.set()
        self.pump(lambda:not self.panel.ask_button.instate(['disabled']))
        self.assertFalse(self.fake.launched); self.assertIsNone(self.panel.task)

    def test_unavailable_balance_is_not_misrepresented_as_zero(self):
        self.panel._account_usage({'balance':None,'ordinary_usage_allowed':None})
        self.assertIn('unavailable',self.panel.credit_status.get())
        self.assertNotIn('0 credits',self.panel.credit_status.get())
        self.assertIn('not reported',self.panel.credit_status.get())

    def test_peer_review_job_cannot_steal_the_developer_answer_or_completion(self):
        self.launch_stage()
        report={'credits':.02,'credit_budget':1,'credit_source':'server_estimate','commands':0,'files':[],'warnings':[]}
        self.panel.emit({'type':'job','thread':'review-1','status':'running'})
        self.panel.emit({'type':'progress','thread':'review-1','report':report,'answer':'Peer review findings.'})
        self.panel.emit({'type':'finished','thread':'review-1','status':'completed',
                         'body':{'answer':'Peer review findings.','error':'','report':report}})
        self.pump(lambda:'Peer review findings.' in self.panel.preview.get('1.0','end'))
        self.assertEqual(self.panel.active_question_thread,'q1')
        self.assertTrue(self.panel.busy)
        self.assertNotIn('Peer review findings.',self.panel.answer_box.get('1.0','end'))
        self.panel.emit({'type':'progress','thread':'q1','report':report,'answer':'Developer result.'})
        self.pump(lambda:'Developer result.' in self.panel.answer_box.get('1.0','end'))
        self.panel.emit({'type':'finished','thread':'q1','status':'completed',
                         'body':{'answer':'Developer result.','error':'','report':report}})
        self.pump(lambda:not self.panel.busy)
        self.assertIn('Developer result.',self.panel.answer_box.get('1.0','end'))

    def test_delayed_launch_receipt_does_not_replace_a_fast_completion_with_working(self):
        self.launch_stage()
        report={'credits':.01,'credit_budget':1,'credit_source':'server_estimate','commands':0,'files':[],'warnings':[]}
        job=self.fake.jobs['q1']
        job.update(status='completed',finished=True)
        self.panel.emit({'type':'finished','thread':'q1','status':'completed',
                         'body':{'answer':'Completed immediately.','error':'','report':report}})
        self.panel.emit({'type':'launched','value':job})
        self.pump(lambda:not self.panel.busy)
        self.assertIn('Completed immediately.',self.panel.answer_box.get('1.0','end'))
        self.assertIn('completed',self.panel.status.get().lower())
        self.assertNotIn('working',self.panel.status.get().lower())

    def test_explicit_browser_retry_recovers_a_running_pane_without_touching_codex(self):
        browser=BrowserController(); self.panel.chat_browser=browser
        self.panel.open_chat()
        self.assertEqual(browser.retried,1)
        self.assertEqual(browser.started,0)
        self.assertIn('Waiting',self.panel.chat_status.get())
        self.assertEqual(self.fake.connected,0); self.assertFalse(self.fake.launched)

    def test_automatic_browser_start_and_draft_do_not_reload_an_active_conversation(self):
        browser=BrowserController(); self.panel.chat_browser=browser; self.panel.start_browser=True
        self.panel.chat_status.set('A conversation is already open.')
        self.panel.route.set('ChatGPT conversation'); self.panel.switch_route()
        self.panel.draft_chat('Selected game context.')
        self.assertEqual(browser.retried,0)
        self.assertEqual(browser.started,2)
        self.assertEqual(browser.commands,[])
        self.assertIn('Selected game context.',self.panel.chat_request.get('1.0','end'))
        self.assertIn('Context added',self.panel.chat_status.get())
        self.assertEqual(self.fake.connected,0); self.assertFalse(self.fake.launched)

    def test_browser_attachment_is_not_reported_as_a_ready_message_box(self):
        self.panel._chat_event({'type':'attached','value':'Browser attached.'})
        self.assertIn('Waiting',self.panel.chat_status.get())
        self.panel._chat_event({'type':'page_state','value':{'composer':True,'sign_in':False,'challenge':False}})
        self.assertIn('message box is ready',self.panel.chat_status.get())

    def test_help_page_and_signed_out_state_have_visible_recovery_guidance(self):
        self.panel._chat_event({'type':'location','value':'https://help.openai.com'})
        self.assertIn('Open / retry ChatGPT',self.panel.chat_status.get())
        self.assertNotIn('Sign in on the page',self.panel.chat_status.get())
        self.panel._chat_event({'type':'page_state','value':{'composer':False,'sign_in':True,'challenge':False}})
        self.assertIn('Sign in',self.panel.chat_status.get())
        self.panel._chat_event({'type':'page_state','value':{'composer':False,'sign_in':False,'challenge':True}})
        self.assertIn('verification',self.panel.chat_status.get())
        self.assertEqual(self.fake.connected,0); self.assertFalse(self.fake.launched)


    def test_native_chat_layout_send_reply_stop_and_codex_handoff(self):
        browser=BrowserController();self.panel.chat_browser=browser
        self.window.update()
        self.assertTrue(self.panel.chat_request.winfo_ismapped())
        self.assertTrue(self.panel.chat_answer.winfo_ismapped())
        self.assertGreater(self.panel.chat_request.winfo_height(),35)
        self.assertGreater(self.panel.chat_answer.winfo_height(),40)
        self.panel.chat_request.insert('1.0','Why does fishing freeze?')
        self.panel.chat_send.invoke()
        self.assertEqual(browser.commands,[('send',{'text':'Why does fishing freeze?'})])
        self.assertFalse(self.fake.launched);self.assertEqual(self.fake.connected,0)
        self.panel._chat_event({'type':'sent','value':'Sent.'})
        self.assertEqual(self.panel.chat_request.get('1.0','end').strip(),'')
        self.panel._chat_event({'type':'conversation','messages':[{'role':'user','text':'Why?'},{'role':'assistant','text':'Check the fishing signal.'}]})
        self.assertIn('Check the fishing signal.',self.panel.chat_answer.get('1.0','end'))
        self.panel.stop_chat()
        self.assertEqual(browser.commands[-1][0],'stop')
        self.panel._chat_event({'type':'stopped','value':'Stopped.'})
        self.assertIn('Check the fishing signal.',self.panel.chat_answer.get('1.0','end'))
        self.panel.chat_request.insert('1.0',"let's implement the changes")
        self.panel.chat_send.invoke()
        self.assertEqual(browser.commands[-1][0],'handoff')
        self.assertFalse(self.fake.launched)

    def test_chat_send_error_retains_question_and_enables_retry(self):
        browser=BrowserController();self.panel.chat_browser=browser
        self.panel.chat_request.insert('1.0','Help with fishing.')
        self.panel.send_chat()
        self.panel._chat_event({'type':'send_error','value':'Sign in on the website.'})
        self.assertIn('Help with fishing.',self.panel.chat_request.get('1.0','end'))
        self.assertIn('Sign in',self.panel.chat_answer.get('1.0','end'))
        self.assertFalse(self.panel.chat_sending)
        self.assertFalse(self.panel.chat_send.instate(['disabled']))

if __name__=='__main__': unittest.main(verbosity=2)
