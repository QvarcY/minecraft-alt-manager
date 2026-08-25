const statusEl=document.getElementById('demoStatus');
const startBtn=document.getElementById('startDemo');
const disconnectBtn=document.getElementById('disconnectDemo');
const resetBtn=document.getElementById('resetDemo');
const clearBtn=document.getElementById('clearLog');
const logEl=document.getElementById('demoLog');
const steps=[...document.querySelectorAll('#workflowSteps>div')];
let timers=[];let running=false;
const stamp=()=>new Date().toLocaleTimeString([],{hour12:false});
function addLog(message,type=''){const row=document.createElement('div');if(type)row.className=type;const time=document.createElement('time');time.textContent=stamp();const text=document.createElement('span');text.textContent=message;row.append(time,text);logEl.append(row);logEl.scrollTop=logEl.scrollHeight}
function setStatus(label,cls){statusEl.textContent=label;statusEl.className=`status ${cls}`}
function clearTimers(){timers.forEach(clearTimeout);timers=[]}
function resetSteps(){steps.forEach(s=>s.classList.remove('active','done'))}
function later(ms,fn){timers.push(setTimeout(fn,ms))}
function resetDemo(){clearTimers();running=false;setStatus('OFFLINE','offline');startBtn.disabled=false;disconnectBtn.disabled=true;resetSteps();addLog('Demo reset. No real server connection is active.')}
function activate(index,message){steps.forEach((s,i)=>{s.classList.toggle('active',i===index);if(i<index)s.classList.add('done')});addLog(message,'success')}
function startDemo(){if(running)return;running=true;clearTimers();resetSteps();startBtn.disabled=true;disconnectBtn.disabled=false;setStatus('CONNECTING','connecting');addLog('Starting ALT profile: survival-alt');addLog('Connecting to play.example.net…');later(700,()=>{setStatus('CONNECTED','online');activate(0,'Connected. Join event detected.')});later(1500,()=>{steps[0].classList.add('done');steps[1].classList.add('active');addLog('WAIT 3s → sending /login ••••')});later(2400,()=>{activate(1,'Login confirmed by server.');addLog('WAIT 3s → sending /server-survival')});later(3400,()=>{activate(2,'Survival server ready.');addLog('WAIT 3s → sending /tp land-home')});later(4400,()=>activate(3,'Destination world loaded.'));later(5000,()=>{steps[3].classList.remove('active');steps[3].classList.add('done');setStatus('AFK','online');addLog('Workflow complete. ALT marked as AFK.','success')})}
function disconnect(){if(!running)return;clearTimers();running=false;setStatus('OFFLINE','offline');startBtn.disabled=false;disconnectBtn.disabled=true;resetSteps();addLog('Disconnected by user.','warning')}
startBtn.addEventListener('click',startDemo);disconnectBtn.addEventListener('click',disconnect);resetBtn.addEventListener('click',resetDemo);clearBtn.addEventListener('click',()=>{logEl.innerHTML='';addLog('Log cleared.')});
