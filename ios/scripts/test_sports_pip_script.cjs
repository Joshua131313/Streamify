// Portable regression checks for the exact JavaScript injected by the Swift
// sports bridge. These exercise lifecycle events, not native AVKit capability.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const swift = fs.readFileSync(path.join(__dirname, '../Streamify/Media/SportsWebPiPBridge.swift'), 'utf8');
const match = swift.match(/return """\r?\n([\s\S]*?)\r?\n\s*"""/);
assert.ok(match, 'The production bridge must contain its injected script.');
const script = match[1].replaceAll('\\(encoded)', JSON.stringify('regression-owner'));

function fixture({ supported = true, hasVideo = true } = {}) {
  const messages = [], videoEvents = new Map(), documentEvents = new Map(), windowEvents = new Map();
  let heartbeat;
  const add = (events, name, action) => events.set(name, [...(events.get(name) ?? []), action]);
  const fire = (events, name) => { for (const action of events.get(name) ?? []) action(); };
  const video = {
    readyState: 4, videoWidth: 640, videoHeight: 360, isConnected: true,
    paused: false, currentTime: 83, currentSrc: 'https://example.com/bravo.m3u8',
    webkitPresentationMode: 'inline', disablePictureInPicture: false,
    getBoundingClientRect() { return { width: 640, height: 360 }; },
    webkitSupportsPresentationMode() { return supported; },
    webkitSetPresentationMode(value) { this.webkitPresentationMode = value; },
    addEventListener(name, action) { add(videoEvents, name, action); }
  };
  const document = {
    hidden: false, querySelectorAll() { return hasVideo ? [video] : []; },
    addEventListener(name, action) { add(documentEvents, name, action); }
  };
  const context = {
    document, Map, WeakMap, Math,
    MutationObserver: class { observe() {} },
    setInterval(action) { heartbeat = action; },
    setTimeout() { throw new Error('Mode reporting must not wait on a timer suspended in the background.'); },
    addEventListener(name, action) { add(windowEvents, name, action); },
    webkit: { messageHandlers: { streamifySportsPiP: { postMessage(body) { messages.push(body); } } } }
  };
  context.window = context;
  vm.runInNewContext(script, context);
  return { video, document, messages, bridge: context.__streamifySportsPiP,
    videoEvent: name => fire(videoEvents, name), documentEvent: name => fire(documentEvents, name),
    windowEvent: name => fire(windowEvents, name), heartbeat: () => heartbeat() };
}

const f = fixture(), id = f.messages[0].id;
assert.equal(f.messages[0].active, false);
assert.equal(f.bridge.request(id), true);
assert.equal(f.messages.at(-1).active, false, 'A request alone cannot confirm that system PiP started.');
f.document.hidden = true;
f.videoEvent('webkitpresentationmodechanged');
assert.equal(f.messages.at(-1).active, true, 'An observed mode must report immediately even while backgrounded.');

// iOS may finish its fullscreen/PiP transition while JavaScript timers are
// suspended. Returning reads the actual video mode rather than waiting for the
// missed event or requesting/reloading the video again.
f.video.webkitPresentationMode = 'fullscreen';
assert.equal(f.bridge.refresh(id), true);
assert.equal(f.messages.at(-1).active, false);
assert.equal(f.messages.at(-1).fullscreen, true);
assert.equal(f.messages.at(-1).kind, 'snapshot');
f.video.webkitPresentationMode = 'inline';
f.document.hidden = false;
f.documentEvent('visibilitychange');
assert.equal(f.messages.at(-1).fullscreen, false);
assert.equal(f.messages.at(-1).active, false);

f.video.webkitPresentationMode = 'fullscreen';
f.videoEvent('webkitbeginfullscreen');
assert.equal(f.messages.at(-1).fullscreen, true);
f.video.webkitPresentationMode = 'inline';
f.videoEvent('webkitendfullscreen');
assert.equal(f.messages.at(-1).fullscreen, false);
f.video.webkitPresentationMode = 'picture-in-picture';
f.windowEvent('pageshow');
assert.equal(f.messages.at(-1).active, true);
f.video.webkitPresentationMode = 'inline';
f.heartbeat();
assert.equal(f.messages.at(-1).active, false, 'A heartbeat recovers a missed mode event as an actual snapshot.');
assert.equal(f.video.currentTime, 83);
assert.equal(f.video.currentSrc, 'https://example.com/bravo.m3u8');
assert.equal(f.video.paused, false, 'Reconciliation must never pause, seek, replace or restart the stream.');

f.video.webkitPresentationMode = 'picture-in-picture';
assert.equal(f.bridge.stop(id), true);
f.video.paused = true;
f.videoEvent('leavepictureinpicture');
assert.equal(f.messages.at(-1).paused, true, 'An actual system close remains distinguishable from restoring playback.');
f.video.isConnected = false;
f.video.webkitPresentationMode = 'fullscreen';
f.heartbeat();
assert.equal(f.messages.at(-1).fullscreen, false, 'A removed video must not retain fullscreen ownership.');

const unsupported = fixture({ supported: false });
assert.equal(unsupported.bridge.request(unsupported.messages[0].id), false);
const empty = fixture({ hasVideo: false });
assert.equal(empty.bridge.request('missing'), false);
assert.equal(empty.bridge.refresh('missing'), false);
console.log('PASS: immediate mode events, fullscreen/PiP restoration, foreground snapshots, source/time retention, system close and unsupported-video handling.');
