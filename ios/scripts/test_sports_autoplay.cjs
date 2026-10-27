const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const ios=path.join(__dirname,'../Streamify/Resources/sports-autoplay.js');
const source=fs.readFileSync(ios,'utf8');
assert.equal(source,fs.readFileSync(path.join(__dirname,'../../android/app/src/main/assets/sports-autoplay.js'),'utf8'),'Both platforms ship the same autoplay policy.');
function fixture(options={}) {
  let timer;const events=new Map(),docEvents=new Map();
  const video={isConnected:true,readyState:options.ready??4,paused:options.paused??true,ended:false,currentTime:0,muted:false,currentSrc:options.source??'https://example.com/live.m3u8',calls:0,querySelector:()=>null,
    getBoundingClientRect:()=>({width:640,height:360}),addEventListener:(name,fn)=>events.set(name,fn),
    play(){this.calls++;if(!options.reject)this.paused=false;return {catch(){}};}};
  const document={hidden:options.hidden??false,querySelectorAll:()=>[video],addEventListener:(n,f)=>docEvents.set(n,f)};
  vm.runInNewContext(source,{WeakSet,Array,document,MutationObserver:class{observe(){}},setInterval:f=>timer=f});
  return {video,document,tick:()=>timer(),event:n=>events.get(n)?.(),docEvent:n=>docEvents.get(n)?.()};
}
const normal=fixture();assert.equal(normal.video.calls,1);assert.equal(normal.video.muted,false);
normal.video.paused=true;normal.video.currentTime=12;normal.event('pause');normal.tick();normal.event('canplay');assert.equal(normal.video.calls,1,'Do not undo a user pause.');
assert.equal(normal.video.currentSrc,'https://example.com/live.m3u8');assert.equal(normal.video.currentTime,12);
const alreadyPlaying=fixture({paused:false});alreadyPlaying.video.paused=true;alreadyPlaying.tick();assert.equal(alreadyPlaying.video.calls,0);
const noPreload=fixture({ready:0});assert.equal(noPreload.video.calls,1,'A source with preload=none must queue play rather than wait forever for canplay.');
const buffering=fixture({ready:0,source:''});buffering.event('pause');buffering.video.readyState=4;buffering.event('canplay');assert.equal(buffering.video.calls,1);
const hidden=fixture({hidden:true});assert.equal(hidden.video.calls,0);hidden.document.hidden=false;hidden.docEvent('visibilitychange');assert.equal(hidden.video.calls,1);
const rejected=fixture({reject:true});rejected.tick();rejected.event('canplay');assert.equal(rejected.video.calls,1,'A blocked source must not retry continuously.');
const removed=fixture({ready:0,source:''});removed.video.readyState=4;removed.video.isConnected=false;removed.tick();assert.equal(removed.video.calls,0);
console.log('PASS: shared sports autoplay starts once, waits for readiness, preserves pause/source/audio, skips hidden/removed videos and tolerates blocked providers.');
