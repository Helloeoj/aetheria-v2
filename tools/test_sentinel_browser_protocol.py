"""Execute browser scripts in an isolated fake DOM; no browser or inference."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

from sentinel_chatgpt_pane import SNAPSHOT_JS, PAGE_STATE_JS, draft_script


class BrowserScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.node = shutil.which('node')
        if not cls.node:
            bundled = Path(sys.executable).parent.parent / 'node' / 'bin' / 'node.exe'
            if bundled.is_file():
                cls.node = str(bundled)
        if not cls.node:
            raise unittest.SkipTest('Node.js is unavailable; browser JavaScript execution checks require Node.')

    def node_json(self, runner, payload):
        result = subprocess.run([self.node, '-e', runner], input=json.dumps(payload),
                                text=True, encoding='utf-8', capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_generated_snapshot_and_multiline_draft_are_valid_javascript(self):
        runner = '''const fs=require('fs');
          const scripts=JSON.parse(fs.readFileSync(0,'utf8'));
          for (const code of scripts) new Function(code);
          console.log(JSON.stringify({compiled:scripts.length}));'''
        result = self.node_json(runner, [SNAPSHOT_JS, PAGE_STATE_JS, draft_script('Game context:\n雪\n"quoted" and \\paths')])
        self.assertEqual(result, {'compiled': 3})

    def test_page_readiness_requires_an_editor_inside_the_visible_viewport(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          const code=JSON.parse(fs.readFileSync(0,'utf8'));
          const sandbox={location:{origin:'https://chatgpt.com'},innerWidth:1000,innerHeight:250,
            getComputedStyle:()=>({display:'block',visibility:'visible'}),
            document:{querySelector:()=>null,querySelectorAll:selector=>selector==='button,a' ? [] :
              [{getBoundingClientRect:()=>({width:500,height:40,top:200,bottom:240,left:10,right:510})}]}};
          const ready=vm.runInNewContext(code,sandbox);
          sandbox.innerHeight=150;const clipped=vm.runInNewContext(code,sandbox);
          sandbox.location.origin='https://help.openai.com';const help=vm.runInNewContext(code,sandbox);
          console.log(JSON.stringify({ready:ready.composer_visible,clipped:clipped.composer_visible,help:help.composer}));'''
        self.assertEqual(self.node_json(runner,PAGE_STATE_JS),{'ready':True,'clipped':False,'help':False})

    def test_draft_preserves_composer_content_and_never_sends_or_handoffs(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          const payload=JSON.parse(fs.readFileSync(0,'utf8'));
          const actions=[];
          const editor={innerText:'My existing question',isContentEditable:true,
            focus(){actions.push('focus')},dispatchEvent(event){actions.push(event.type)},
            requestSubmit(){throw Error('Draft submitted')},click(){throw Error('Draft clicked')}};
          const sandbox={location:{origin:'https://chatgpt.com'},window:{getSelection(){return {
            removeAllRanges(){},addRange(){}}}},Event:class{constructor(type){this.type=type}},
            document:{querySelector(selector){if(selector!=='#prompt-textarea') throw Error('Unexpected UI access');return editor},
            createRange(){return {selectNodeContents(){}}},
            execCommand(command,unused,text){actions.push(command);editor.innerText=text;return true}}};
          const inserted=vm.runInNewContext(payload,sandbox);
          console.log(JSON.stringify({inserted,text:editor.innerText,actions,
            armed:!!sandbox.window.__sentinelChat}));'''
        context = 'Game context:\n雪 and "quotes"\nNo automatic send.'
        result = self.node_json(runner, draft_script(context))
        self.assertEqual(result['text'], 'My existing question\n\n' + context)
        self.assertEqual(result['actions'], ['focus', 'insertText', 'input'])
        self.assertTrue(result['inserted'])
        self.assertFalse(result['armed'])

    def test_mobile_textarea_draft_uses_native_value_setter_without_submitting(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          class Area {set value(value){this._value=value} get value(){return this._value}}
          const editor=new Area();editor.value='Original';editor.focus=()=>{};
          let inputs=0;editor.dispatchEvent=e=>{if(e.type==='input')inputs++};
          const sandbox={location:{origin:'https://chatgpt.com'},HTMLTextAreaElement:Area,
            Event:class{constructor(type){this.type=type}},
            document:{querySelector(selector){return selector==='#mobile-composer-prompt' ? editor : null}}};
          const result=vm.runInNewContext(JSON.parse(fs.readFileSync(0,'utf8')),sandbox);
          console.log(JSON.stringify({result,text:editor.value,inputs}));'''
        result = self.node_json(runner, draft_script('Additional context'))
        self.assertEqual(result, {'result': True, 'text': 'Original\n\nAdditional context', 'inputs': 1})

    def test_old_messages_and_synthetic_submit_cannot_arm_a_handoff(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          const code=JSON.parse(fs.readFileSync(0,'utf8')),listeners={};
          const sandbox={location:{origin:'https://chatgpt.com',href:'https://chatgpt.com/c/old'},window:{},Date,
            document:{addEventListener(type,callback){listeners[type]=callback},
              querySelector(){return {innerText:'Implement the changes'}},
              querySelectorAll(){return [{dataset:{messageAuthorRole:'user'},innerText:'Implement the changes'}]}}};
          const first=vm.runInNewContext(code,sandbox);
          listeners.keydown({key:'Enter',shiftKey:false,isTrusted:false});
          const second=vm.runInNewContext(code,sandbox);
          console.log(JSON.stringify({first:first.requested,second:second.requested,pending:sandbox.window.__sentinelChat.submit}));'''
        self.assertEqual(self.node_json(runner, SNAPSHOT_JS), {'first': False, 'second': False, 'pending': None})

    def test_trusted_mobile_submission_requests_only_one_handoff(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          const code=JSON.parse(fs.readFileSync(0,'utf8')),listeners={};
          const sandbox={location:{origin:'https://chatgpt.com',href:'https://chatgpt.com/c/one'},window:{},Date,
            document:{addEventListener(type,callback){listeners[type]=callback},
              querySelector(selector){return selector==='#mobile-composer-prompt' ? {value:"let's implement the changes"} : null},
              querySelectorAll(){return [{dataset:{messageAuthorRole:'user'},innerText:"let's implement the changes"}]}}};
          vm.runInNewContext(code,sandbox);
          listeners.keydown({key:'Enter',shiftKey:false,isTrusted:true});
          const first=vm.runInNewContext(code,sandbox),second=vm.runInNewContext(code,sandbox);
          console.log(JSON.stringify({first:first.requested,second:second.requested}));'''
        self.assertEqual(self.node_json(runner,SNAPSHOT_JS),{'first':True,'second':False})

    def test_draft_rejects_other_origins_without_touching_the_composer(self):
        runner = '''const fs=require('fs'),vm=require('vm');
          const sandbox={location:{origin:'https://example.com'},document:{
            querySelector(){throw Error('Unexpected cross-origin access')}}};
          console.log(JSON.stringify(vm.runInNewContext(JSON.parse(fs.readFileSync(0,'utf8')),sandbox)));'''
        self.assertIs(self.node_json(runner, draft_script('Context')), False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
