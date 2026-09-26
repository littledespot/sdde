'use strict';
const $ = id => document.getElementById(id);
const token = location.hash.slice(1);
let calls = [], selected = -1, tab = 'Prompt', busy = false, sourceSelection = null;
const tabs = ['Prompt', 'Context', 'Schema', 'Request', 'Response', 'Sources', 'Replay'];
function callKind(c) {
 switch (c.kind) {
  case 'initial': return {label:'Initial', relation:null};
  case 'repair': return {label:'Repair', relation:'Repair of'};
  case 'retry': return {label:'Retry', relation:'Retry of'};
  case 'context_followup': return {label:'Context follow-up', relation:'Follow-up to'};
  case 'replay': return {label:c.replay === 'modified' ? 'Modified replay' : 'Exact replay', relation:'Replay of'};
  default: throw Error('Unknown captured call kind: ' + c.kind);
 }
}
function kindBadge(c) { return tag(callKind(c).label, 'kind kind-' + c.kind); }
function callReference(index, from) {
 const target = calls[index];
 return 'Call ' + target.execution_order + (target.run === from.run ? '' : ' · ' + target.run);
}
function parentDescription(c) {
 const relation = callKind(c).relation;
 if (!relation) return 'First call in this request chain';
 const index = parentIndex(c);
 if (index >= 0) return relation + ' ' + callReference(index, c);
 return c.parent ? relation + ' ' + c.parent + ' (not in this capture)' : 'Source call not recorded';
}
function el(tag, text, cls) { const e = document.createElement(tag); if (text != null) e.textContent = String(text); if (cls) e.className = cls; return e; }
function pre(text) { return el('pre', text ?? 'Unavailable in this capture.'); }
function button(text, fn, cls = 'secondary') { const b = el('button', text, cls); b.type = 'button'; b.onclick = fn; return b; }
function card(title) { const c = el('div', null, 'card'); c.append(el('h2', title)); return c; }
function status(call) { const v = call.validation; if (call.response_status && call.response_status !== 200) return 'HTTP ' + call.response_status; return v.schema === 'valid' ? 'SCHEMA VALID' : v.schema === 'invalid' ? 'SCHEMA INVALID' : v.json === 'invalid' ? 'INVALID JSON' : call.response_provenance ?? 'AWAITING RESPONSE'; }
function tag(text, kind) { return el('span', text, 'tag' + (kind ? ' ' + kind : '')); }
function showError(message) { $('error').textContent = message; $('error').hidden = !message; }
async function api(path, data) { const response = await fetch(path, {method:data ? 'POST' : 'GET', headers:{'X-SDDE-Debugger-Token':token, ...(data ? {'Content-Type':'application/json'} : {})}, ...(data ? {body:JSON.stringify(data)} : {})}); if (!response.ok) throw Error(await response.text()); return response.json(); }
function nav() {
 $('count').textContent = calls.length;
 const filter = $('search').value.toLowerCase();
 $('calls').replaceChildren();
 let run = null;
 calls.forEach((c, i) => {
  const order = 'Call ' + c.execution_order;
  if ($('kind-filter').value && c.kind !== $('kind-filter').value) return;
  if (![c.workflow,c.node,c.request_step,c.action,c.slot,c.id,c.kind,callKind(c).label,c.run,order,parentDescription(c),c.source_snapshot?.document.path,...(c.source_snapshot?.caller.chain.map(x=>x.id)??[])].join(' ').toLowerCase().includes(filter)) return;
  if (run !== c.run) {
   run = c.run;
   const group = el('div', null, 'run-group');
   group.append(el('strong', c.replay ? 'Replay session' : 'Workflow run'), el('small', run));
   $('calls').append(group);
  }
  const b = button('', () => choose(i), 'call' + (selected === i ? ' selected' : ''));
  const top = el('div', null, 'call-top');
  top.append(el('span', order, 'call-order'), kindBadge(c));
  b.append(top, el('span', (c.replay ? 'Source workflow: ' : 'Workflow: ') + c.workflow, 'call-workflow'), el('small', c.replay ? 'Captured YAML call entry' : 'YAML call entry', 'call-origin-label'), el('strong', c.source_snapshot?.caller.chain[0]?.id ?? c.node), el('small', 'Action: ' + c.action, 'call-action'), el('small', parentDescription(c), 'call-source'), el('small', c.id), tag(status(c), c.validation.schema === 'valid' ? 'good' : c.validation.schema === 'invalid' ? 'bad' : ''));
  $('calls').append(b);
 });
}
function choose(i) { sourceSelection = null; selected = i; nav(); render(); }
function same(a,b) { return JSON.stringify(a) === JSON.stringify(b); }
function parentIndex(c) { return calls.findIndex(x => x.id === c.parent && x.run === (c.parent_run ?? c.run)); }
function renderWorkflowOrigin(c) {
 const box = $('origin');
 box.replaceChildren(el('h2', c.replay ? 'Captured workflow origin' : 'Workflow origin'));
 const fields = el('dl', null, 'origin-fields');
 const entries = [
  [c.replay ? 'Source workflow' : 'Workflow', c.workflow],
  ['Action executed', c.action],
  [c.replay ? 'Captured YAML call entry (expanded)' : 'Calling YAML entry (expanded)', c.node],
  [c.replay ? 'Captured request-preparation entry' : 'Request-preparation entry', c.request_step],
  ['Model slot', c.slot]
 ];
 entries.forEach(([label, value]) => {
  const row = el('div');
  const detail = el('dd');
  detail.append(el('code', value));
  row.append(el('dt', label), detail);
  fields.append(row);
 });
 box.append(fields);
 sourceNavigation(box,c);
 box.append(el('p', c.replay
  ? 'Initiated by your Replay command. These entries identify the captured request; replay does not execute a workflow node.'
  : 'The calling YAML entry dispatched this call. The request-preparation entry assembled its prompt, context and schema. Entry IDs include expanded subgraph instances.', 'note'));
}
function render() {
 const c = calls[selected]; $('empty').hidden = !!c; $('detail').hidden = !c; if (!c) return;
 $('workflow').textContent = c.workflow; $('title').textContent = c.node;
 $('meta').replaceChildren(tag('Call ' + c.execution_order),kindBadge(c),tag(c.id),tag(c.action),tag(c.description?.model ?? c.slot),tag(status(c),c.validation.schema === 'valid' ? 'good' : c.validation.schema === 'invalid' ? 'bad' : ''));
 const links = el('div', null, 'lineage-links');
 const pi = parentIndex(c);
 links.append(pi >= 0 ? button('← ' + parentDescription(c), () => choose(pi), 'link') : el('span', parentDescription(c)));
 const root = calls.findIndex(x => x.run === (c.original_run ?? c.run) && x.id === c.original);
 if (root >= 0 && root !== selected && root !== pi) links.append(button('Original: ' + callReference(root, c), () => choose(root), 'link'));
 $('lineage').replaceChildren(links, el('small','Run ' + c.run, 'subtle'));
 renderWorkflowOrigin(c);
 $('tabs').replaceChildren(...tabs.map(t => { const b = button(t, () => {tab=t;render();}, t===tab?'active':''); b.setAttribute('aria-current', t===tab?'page':'false'); return b; }));
 const p=$('panel');p.replaceChildren(); const d=c.description;
 if (!d && ['Prompt','Context','Schema','Replay'].includes(tab)) { p.append(el('div','This exchange has no complete request description. Enable debug or trace and capture a new call.','empty-box')); return; }
 if (tab==='Prompt') { const protocol=card('Protocol prompt');protocol.append(pre(d.protocol_prompt));p.append(protocol);let n=0;d.content.forEach(part=>{const [kind,text]=Object.entries(part)[0];if(kind==='guidance'||kind==='system'){const box=card((++n===1?'Task prompt':'Additional prompt '+n)+' · '+kind);box.append(pre(text));p.append(box);}}); }
 if (tab==='Context') { d.content.forEach((part,i)=>{const [kind,text]=Object.entries(part)[0];if(kind!=='user'&&kind!=='evidence')return;const box=card('Context '+(i+1)+' · '+kind), top=el('div',null,'card-top'), toggles=el('div',null,'toggle'), body=el('div');let view='structured';function draw(){body.replaceChildren();if(view==='raw'){body.append(pre(text));return;}try{body.append(tree(JSON.parse(text),'Generation input',0));}catch{body.append(pre(text));}}const structured=button('Structured',()=>{view='structured';structured.className='active';raw.className='';draw();},'active'),raw=button('Raw',()=>{view='raw';raw.className='active';structured.className='';draw();},'');toggles.append(structured,raw);top.append(el('span','Exact content; structure is a display view.','subtle'),toggles);box.append(top,body);draw();p.append(box);}); }
 if (tab==='Schema') { const box=card('Validation schema');box.append(pre(d.schema),el('p','Captured acceptance schema. The Request view contains the exact model-facing schema representation.','note'));p.append(box); }
 if (tab==='Request') { const box=card('Exact provider request');box.append(pre(c.request),el('p',c.request_complete?'All captured request bytes are present.':'Incomplete capture: replay is disabled.','note'));if(c.redacted)box.append(el('p','Credentials were redacted. Exact replay is disabled.','note'));p.append(box);const info=card('Caller');info.append(pre(JSON.stringify({workflow:c.workflow,action:c.action,yaml_entry:c.node,request_entry:c.request_step,model_slot:c.slot,run:c.run,execution_order:c.execution_order,sequence:c.sequence,call:c.id,original:c.original,parent:c.parent,provider:d?.provider,model:d?.model,settings:d?{...d.controls,reasoning_effort:d.reasoning_effort,response_mode:d.response_mode}:null},null,2)));p.append(info); }
 if (tab==='Response') { const v=c.validation; const flow=card('Response admission');flow.append(el('p',`Provider bytes → Extracted text: ${v.extraction} → JSON: ${v.json} → Schema: ${v.schema}`));if(v.normalization==='removed_leading_brace_quote')flow.append(el('p','JSON normalized: removed the leading brace and quote (2 bytes) after syntax failure. Original response preserved.','note'));if(c.response_diagnostic)flow.append(pre(c.response_diagnostic));if(c.response_encoding==='base64')flow.append(el('p','Raw response bytes are displayed as base64.','note'));if(v.reason){flow.append(tag(v.reason,'bad'));if(v.path!=null)flow.append(pre(v.path || '/'));if(v.expected)flow.append(el('p',`Expected: ${v.expected} · Received: ${v.received}`));}flow.append(el('p','Schema checks are diagnostic. Semantic workflow validators are not rerun for a replay.','note'));p.append(flow);[['Raw provider response · '+(c.response_provenance??'unavailable'),c.response],['Extracted model text',v.model_text],['Parsed structured response',v.parsed==null?null:JSON.stringify(v.parsed,null,2)]].forEach(([title,text])=>{const box=card(title);box.append(pre(text));p.append(box);});const events=card('Recorded workflow validation');events.append(c.events.length?pre(JSON.stringify(c.events,null,2)):el('p','No correlated workflow validation events in this record.','subtle'));p.append(events); }
 if (tab==='Sources') sourceView(p,c);
 if (tab==='Replay') replayView(p,c,d);
}

function sourceSelector(entry) { return (entry.subgraph ? '/subgraphs/'+entry.subgraph : '')+'/steps/'+entry.id; }
function openSource(selection) { sourceSelection=selection;tab='Sources';render(); }
function sourceNavigation(box,c) {
 const source=c.source_snapshot;
 if(!source){box.append(el('p','Source files were not captured for this call. Authored YAML and resource links are unavailable.','note'));return;}
 const links=el('div',null,'source-navigation');
 [['caller','Call chain'],['preparation','Request assembly']].forEach(([key,title])=>{
  const row=el('div',null,'source-chain');row.append(el('strong',title));
  source[key].chain.forEach((entry,index)=>{
   if(index)row.append(el('span',' → ','subtle'));
   const b=button(entry.id+' · '+entry.target,()=>openSource({key,index}),'link');
   b.title=source.document.path+' #'+sourceSelector(entry);row.append(b);
  });links.append(row);
 });
 const resources=el('div',null,'source-chain');resources.append(el('strong','Bound resources'));
 source.resources.forEach((resource,index)=>resources.append(button(resource.role.replaceAll('_',' ')+' · '+resource.alias,()=>openSource({key:'resource',index}),'link')));
 resources.append(button('Exact assembled request',()=>{tab='Request';render();},'link'));
 links.append(resources);box.append(links);
 if(c.source_overrides)box.append(el('p','Replay overrides are present. These source snapshots belong to the original workflow call; the Prompt, Context, Schema and Request tabs show this replay’s actual input.','note'));
}
function sourceView(panel,c) {
 const source=c.source_snapshot;
 if(!source){panel.append(el('div','No source snapshot in this capture. Capture a new call at debug or trace to retain its workflow and bound resource files.','empty-box'));return;}
 const selectedSource=sourceSelection??{key:'caller',index:0};
 let document=source.document;
 if(selectedSource.key==='resource'){
  const resource=source.resources[selectedSource.index];document=resource.document;
  const binding=card(resource.role.replaceAll('_',' ')+' · '+resource.alias);
  binding.append(el('p','Workflow resource alias: '+resource.alias+' → '+document.path),el('p','Kind: '+resource.kind,'subtle'));
  if(resource.role==='result'||resource.role==='composition'){
   if(source.selection.definition)binding.append(el('p','Selected schema definition: '+source.selection.definition));
   if(source.selection.part)binding.append(el('p','Selected composition part: '+source.selection.part));
   if(source.selection.paths.length)binding.append(pre(source.selection.paths.map(parts=>'/'+parts.map(x=>x.replaceAll('~','~0').replaceAll('/','~1')).join('/')).join('\n')));
  }
  panel.append(binding);
 }else{
  const location=source[selectedSource.key],entry=location.chain[selectedSource.index];
  const declaration=card('Authored YAML entry · '+entry.id);
  declaration.append(el('p',document.path+' #'+sourceSelector(entry)),el('p','Expanded entry: '+location.step,'subtle'),el('p','Structured view of the captured authored entry. The full raw YAML snapshot is below.','note'),pre(entry.declaration));
  panel.append(declaration);
 }
 const raw=card('Captured file · '+document.path);
 raw.append(el('p',document.redacted?'Credential-redacted snapshot from this execution.':'Exact file bytes retained from this execution.','note'),pre(document.content));
 panel.append(raw);
 if(c.source_overrides)panel.append(el('p','Source files describe the original workflow input. Replay edits override the assembled request and do not modify these files.','note'));
}

function tree(value,name,depth){if(value===null||typeof value!=='object'){const row=el('div',null,'leaf');row.append(el('span',name+': ','key'),el('span',JSON.stringify(value)));return row;}const box=el('details');box.open=depth<2;const keys=Object.keys(value),summary=el('summary',name);summary.append(el('span',Array.isArray(value)?`${value.length} items`:`${keys.length} fields`));box.append(summary);keys.forEach(key=>box.append(tree(value[key],Array.isArray(value)?'['+key+']':key,depth+1)));return box;}
function replayView(p,c,d){const intro=card('Replay one prompt');intro.append(el('p','Send this selected request once, with the same provider, model and settings. No other workflow steps run. A new linked record preserves the original.'));const actions=el('div',null,'actions'),exact=button(busy?'Waiting for provider…':'Exact replay · one call',()=>replay('exact',null),'primary');exact.disabled=busy||!c.request_complete||c.redacted||d.operation_kind!=='inference';actions.append(exact,el('p','A replay sends a new provider request and may incur charges.'));intro.append(actions);if(!c.request_complete||c.redacted)intro.append(el('p','Exact replay requires a complete, unredacted request.','note'));p.append(intro);
 const editor=card('Modified replay'),fields=[];editor.append(el('p','Edit the prompt, context or schema for this call. The protocol prompt and model settings stay fixed.','note'));d.content.forEach((part,i)=>{const [kind,text]=Object.entries(part)[0],label=el('label',(kind==='guidance'||kind==='system'?'Prompt':'Context')+' '+(i+1)+' · '+kind),area=el('textarea');area.value=text;area.id='edit-'+i;area.spellcheck=false;label.htmlFor=area.id;editor.append(label,area);fields.push({kind,area});});const label=el('label','Schema'),schema=el('textarea',null,'schema');schema.id='edit-schema';schema.value=d.schema;schema.spellcheck=false;label.htmlFor=schema.id;editor.append(label,schema);const go=button(busy?'Waiting for provider…':'Replay edited prompt · one call',()=>replay('modified',{content:fields.map(x=>({[x.kind]:x.area.value})),schema:schema.value}),'primary');go.disabled=busy||!c.request_complete||d.operation_kind!=='inference';const row=el('div',null,'actions');row.append(go);editor.append(row);p.append(editor);
 const pi=parentIndex(c);if(pi>=0){const parent=calls[pi],compare=card('Original / replay comparison'),table=el('table');const rows=[['','Parent call','Selected replay'],['Model',parent.description?.model,d.model],['Prompt', 'Original',same(parent.description?.content.filter(x=>x.guidance!==undefined||x.system!==undefined),d.content.filter(x=>x.guidance!==undefined||x.system!==undefined))?'Identical':'Modified'],['Context','Original',same(parent.description?.content.filter(x=>x.user!==undefined||x.evidence!==undefined),d.content.filter(x=>x.user!==undefined||x.evidence!==undefined))?'Identical':'Modified'],['Schema','Original',parent.description?.schema===d.schema?'Identical':'Modified'],['Input tokens',parent.validation.input_tokens,c.validation.input_tokens],['Output tokens',parent.validation.output_tokens,c.validation.output_tokens],['Latency (ms)',parent.validation.latency_ms,c.validation.latency_ms],['Result',status(parent),status(c)]];rows.forEach((cells,i)=>{const tr=el('tr');cells.forEach(value=>tr.append(el(i?'td':'th',value??'Unavailable')));table.append(tr);});compare.append(table);p.append(compare);}}
async function replay(mode,edit){if(busy)return;busy=true;showError('');const call=selected;render();try{calls=await api('/api/replay',{call,mode,edit});selected=calls.length-1;sourceSelection=null;tab='Replay';}catch(error){showError(error.message);}finally{busy=false;nav();render();}}
$('search').oninput=nav;
$('kind-filter').onchange=nav;
api('/api/calls').then(data=>{calls=data;nav();if(calls.length)choose(0);else $('empty-note').textContent='No captured calls. Run a workflow with logs.level set to debug or trace, then open its feature directory here.';}).catch(error=>{showError(error.message);$('empty-note').textContent='Could not load captured calls.';});
