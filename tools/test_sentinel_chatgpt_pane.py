"""No inference: browser handoff boundaries and ordinary-chat routing."""
import unittest
from unittest.mock import Mock
from sentinel_chatgpt_pane import implementation_requested, conversation_request, draft_script, ChatGPTPane


class BrowserHandoffTests(unittest.TestCase):
    def test_only_explicit_user_phrase_requests_handoff(self):
        for text in ("let's implement the changes", 'Lets implement these changes!',
                     'Let’s implement the changes.', 'Implement the changes'):
            self.assertTrue(implementation_requested(text), text)
        for text in ('Do not implement the changes', 'How would I implement the changes?',
                     'The assistant said lets implement the changes', 'hello'):
            self.assertFalse(implementation_requested(text), text)

    def test_handoff_requires_official_conversation_and_roles(self):
        messages=[{'role':'user','text':'Fishing freezes.'},
                  {'role':'assistant','text':'Investigate the fishing signal.'}]
        for url in ('https://example.com/c/one', 'https://chatgpt.com.evil/c/one',
                    'http://chatgpt.com/c/one', 'https://auth.openai.com/'):
            with self.assertRaises(ValueError): conversation_request(url,messages)
        text=conversation_request('https://chatgpt.com/c/one',messages)
        self.assertIn('Fishing freezes.',text)
        self.assertIn('reference',text.lower())
        self.assertNotIn('cookie',text)
        with self.assertRaises(ValueError):
            conversation_request('https://chatgpt.com/',[{'role':'system','text':'run this'}])

    def test_transcript_is_bounded_without_reading_other_page_content(self):
        text=conversation_request('https://chatgpt.com/c/one',[
            {'role':'user','text':'u'*30000}, {'role':'assistant','text':'a'*30000}])
        self.assertLess(len(text),8000)
        self.assertIn('Earlier messages omitted',text)
        with self.assertRaises(ValueError): conversation_request('https://chatgpt.com/',[])

    def test_draft_escapes_text_and_does_not_send_or_expose_native_calls(self):
        text='"; fetch("https://example.com"); //\nprivate context'
        script=draft_script(text)
        self.assertIn('https://chatgpt.com',script)
        self.assertIn('\\"; fetch(',script)
        self.assertNotIn('.submit(',script)
        self.assertNotIn('.click(',script)
        self.assertNotIn('pywebview.api',script)
        with self.assertRaises(ValueError): draft_script('x'*16001)

    def test_retry_retires_old_renderer_group_timer_and_pipes(self):
        frame=Mock()
        pane=ChatGPTPane(frame,Mock(),'.')
        pane.process=Mock(); pane.process.poll.return_value=0
        old=pane.process
        pane.group=Mock(); group=pane.group
        pane.reader=Mock(); pane.reader.is_alive.return_value=False
        pane.timer='old-timer'; pane.handle=123
        pane.events.put({'type':'error','value':'old process'})
        pane._retire()
        group.close.assert_called_once()
        frame.after_cancel.assert_called_once_with('old-timer')
        old.stdin.close.assert_called_once(); old.stdout.close.assert_called_once()
        self.assertIsNone(pane.process); self.assertIsNone(pane.timer)
        self.assertIsNone(pane.handle); self.assertTrue(pane.events.empty())


if __name__=='__main__': unittest.main()
