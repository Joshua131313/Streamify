// Exercises the actual injected script in isolated fake cross-origin frames.
// No browser, stream provider, account, or network connection is used.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../Streamify/Sports/SportsMultiWatchView.swift', import.meta.url), 'utf8');
const script = source.match(/private static var audioScript: String\s*\{\s*"""([\s\S]*?)"""/)?.[1];
assert.ok(script, 'Extract the production Swift WKUserScript rather than a copied implementation.');

const settle = () => new Promise(resolve => setImmediate(resolve));
async function flush() { for (let n = 0; n < 5; n++) await settle(); }
function observe(promise) {
    const state = { settled: false, error: undefined, value: undefined };
    state.done = promise.then(value => { state.settled = true; state.value = value; }, error => {
        state.settled = true; state.error = error;
    });
    return state;
}

class Frames {
    timers = new Map();
    nextTimer = 0;
    held = [];
    sent = [];
    ready = [];

    create(name, parent = null, install = true) {
        const harness = this;
        const listeners = new Map(), mutations = [], proxies = new Map();
        const frame = { name, media: [], holdAcknowledgements: false, window: null };
        class Media {
            constructor() { this.value = false; }
            get muted() { return this.value; }
            set muted(value) { this.value = Boolean(value); }
        }
        const window = {
            HTMLMediaElement: Media,
            frames: [],
            addEventListener(type, callback) {
                const callbacks = listeners.get(type) ?? [];
                callbacks.push(callback); listeners.set(type, callbacks);
            },
            document: {
                querySelectorAll(selector) { assert.equal(selector, 'video,audio'); return frame.media; },
                addEventListener() {},
            },
            MutationObserver: class {
                constructor(callback) { mutations.push(callback); }
                observe() {}
            },
            setTimeout(callback) {
                const id = ++harness.nextTimer;
                harness.timers.set(id, { frame, callback });
                return id;
            },
            clearTimeout(id) { harness.timers.delete(id); },
            webkit: { messageHandlers: { streamifyTileAudio: {
                postMessage(message) { harness.ready.push({ frame, message }); },
            } } },
        };
        frame.window = window;
        frame.reference = target => {
            if (target === frame) return window;
            if (!proxies.has(target)) proxies.set(target, {
                postMessage(data) { harness.send(frame, target, data); },
            });
            return proxies.get(target);
        };
        frame.receive = (sender, data) => {
            for (const callback of listeners.get('message') ?? []) {
                callback({ source: frame.reference(sender), data });
            }
        };
        window.window = window;
        window.parent = parent ? frame.reference(parent) : window;
        window.postMessage = data => harness.send(frame, frame, data);
        if (parent) parent.window.frames.push(parent.reference(frame));
        frame.appendMedia = () => {
            const media = new Media(); frame.media.push(media);
            for (const callback of mutations) callback();
            return media;
        };
        frame.appendMedia();
        if (install) vm.runInNewContext(script, window, { timeout: 1000, filename: `audio-${name}.js` });
        return frame;
    }

    send(sender, receiver, data) {
        this.sent.push({ sender, receiver, data });
        const deliver = () => receiver.receive(sender, data);
        if (sender.holdAcknowledgements && data.streamifyAudioAck) this.held.push({ sender, deliver });
        else queueMicrotask(deliver);
    }
    release(frame) {
        const messages = this.held.filter(message => message.sender === frame);
        this.held = this.held.filter(message => message.sender !== frame);
        for (const message of messages) queueMicrotask(message.deliver);
    }
    expire(frame) {
        for (const [id, timer] of [...this.timers]) {
            if (timer.frame === frame) { this.timers.delete(id); timer.callback(); }
        }
    }
}

const tests = [];
async function test(name, run) { await run(); tests.push(name); console.log(`PASS ${name}`); }

await test('Unselected media starts muted and provider writes cannot unmute it', async () => {
    const frames = new Frames(), root = frames.create('root'), child = frames.create('child', root);
    assert.ok(root.media[0].muted && child.media[0].muted);
    child.media[0].muted = false;
    assert.equal(child.media[0].muted, true);
    assert.equal(child.appendMedia().muted, true, 'Dynamically inserted media follows the current muted state.');
    assert.equal(frames.ready.length, 2, 'Every document announces readiness to native audio coordination.');
});

await test('The command waits for descendant-frame acknowledgements', async () => {
    const frames = new Frames(), root = frames.create('root'), child = frames.create('child', root);
    const nested = frames.create('nested', child);
    nested.holdAcknowledgements = true;
    const command = observe(root.window.__streamifySetAudible(true));
    await flush();
    assert.equal(command.settled, false, 'The root cannot acknowledge before its grandchild.');
    assert.ok([root, child, nested].every(frame => !frame.media[0].muted));
    frames.release(nested);
    await command.done;
    assert.equal(command.error, undefined);
    assert.equal(frames.timers.size, 0);
});

await test('A failed frame does not short-circuit other outstanding mute acknowledgements', async () => {
    const frames = new Frames(), root = frames.create('root'), failing = frames.create('failing', root);
    frames.create('not-ready', failing, false);
    const slow = frames.create('slow', root);
    slow.holdAcknowledgements = true;
    const command = observe(root.window.__streamifySetAudible(false));
    await flush();
    frames.expire(failing);
    await flush();
    assert.equal(command.settled, false, 'Even after one failure, the remaining mute barrier must settle.');
    frames.release(slow);
    await command.done;
    assert.match(command.error?.message ?? '', /acknowledge/);
    assert.equal(frames.timers.size, 0);
});

await test('Late frame readiness re-enters the native mute barrier before inheriting selected audio', async () => {
    const frames = new Frames(), root = frames.create('root');
    await root.window.__streamifySetAudible(true);
    const late = frames.create('late-provider-frame', root);
    assert.equal(late.media[0].muted, true, 'A late frame must never decide to unmute itself.');
    assert.equal(frames.ready.at(-1).frame, late);
    assert.equal(frames.ready.at(-1).message.ready, true);
    // Model the native coordinator's public contract, not its Swift algorithm:
    // readiness requests a full mute acknowledgement before selected unmute.
    await root.window.__streamifySetAudible(false);
    assert.ok(root.media[0].muted && late.media[0].muted);
    await root.window.__streamifySetAudible(true);
    assert.ok(!root.media[0].muted && !late.media[0].muted);
});

await test('An acknowledgement from a different frame cannot satisfy another frame request', async () => {
    const frames = new Frames(), root = frames.create('root'), held = frames.create('held', root);
    const sibling = frames.create('sibling', root);
    held.holdAcknowledgements = true;
    const command = observe(root.window.__streamifySetAudible(false));
    await flush();
    const request = frames.sent.find(message => message.receiver === held && message.data.streamifyAudio);
    frames.send(sibling, root, { streamifyAudioAck: true, requestID: request.data.requestID, ok: true });
    await flush();
    assert.equal(command.settled, false);
    frames.release(held);
    await command.done;
    assert.equal(command.error, undefined);
});

await test('Late acknowledgements from a superseded unmute cannot restore audio after mute', async () => {
    const frames = new Frames(), root = frames.create('root'), child = frames.create('child', root);
    child.holdAcknowledgements = true;
    const oldCommand = observe(root.window.__streamifySetAudible(true));
    await flush();
    const mute = observe(root.window.__streamifySetAudible(false));
    await flush();
    assert.ok(root.media[0].muted && child.media[0].muted);
    frames.release(child);
    await Promise.all([oldCommand.done, mute.done]);
    assert.equal(oldCommand.error, undefined);
    assert.equal(mute.error, undefined);
    assert.ok(root.media[0].muted && child.media[0].muted);
    assert.equal(frames.timers.size, 0);
});

console.log(JSON.stringify({ passed: tests.length, failed: 0, source: 'SportsMultiWatchView.audioScript', tests }));
