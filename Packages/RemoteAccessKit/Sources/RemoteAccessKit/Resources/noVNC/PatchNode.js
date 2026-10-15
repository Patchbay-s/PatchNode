// PatchNode bridge for noVNC: the RFB stream comes from the app (a native
// websocket that carries the API token in its header), not from the page.
// The page has no network access at all (Content-Security-Policy).
import RFB from './core/rfb.js';
import KeyTable from './core/input/keysym.js';
import keysyms from './core/input/keysymdef.js';

const post = (message) => window.webkit.messageHandlers.vnc.postMessage(message);

function toBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
}

function fromBase64(text) {
    const binary = atob(text);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
    return bytes.buffer;
}

// What noVNC expects from a WebSocket or an RTCDataChannel.
class NativeChannel {
    constructor() {
        this.binaryType = 'arraybuffer';
        this.protocol = '';
        this.readyState = 'open';
        this.onopen = null;
        this.onmessage = null;
        this.onclose = null;
        this.onerror = null;
    }
    send(data) {
        if (this.readyState !== 'open') { return; }
        const buffer = data instanceof ArrayBuffer ? data : data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
        post({ type: 'send', data: toBase64(buffer) });
    }
    close() {
        if (this.readyState === 'closed') { return; }
        this.readyState = 'closed';
        post({ type: 'close' });
        if (this.onclose) { this.onclose({ code: 1000, reason: '', wasClean: true }); }
    }
}

let rfb = null;
let channel = null;

const keyboard = document.getElementById('keyboard');

// Soft keyboard (iPhone, iPad without keyboard): typed characters become key
// presses. A hardware keyboard reaches noVNC's own handlers on the canvas.
keyboard.addEventListener('input', (event) => {
    if (!rfb) { return; }
    const type = event.inputType || '';
    if (type === 'deleteContentBackward') {
        rfb.sendKey(KeyTable.XK_BackSpace, 'Backspace');
    } else if (type === 'insertLineBreak' || type === 'insertParagraph') {
        rfb.sendKey(KeyTable.XK_Return, 'Enter');
    } else if (event.data) {
        for (const character of event.data) {
            rfb.sendKey(keysyms.lookup(character.codePointAt(0)));
        }
    }
    keyboard.value = '';
});

window.PatchNode = {
    start(password, scale) {
        channel = new NativeChannel();
        rfb = new RFB(document.getElementById('screen'), channel, { credentials: { password } });
        rfb.scaleViewport = scale;
        rfb.clipViewport = !scale;
        rfb.resizeSession = false;
        rfb.focusOnClick = true;
        rfb.background = '#000';
        rfb.addEventListener('connect', () => post({ type: 'connected' }));
        rfb.addEventListener('disconnect', (e) => post({ type: 'disconnected', clean: !!e.detail.clean }));
        rfb.addEventListener('securityfailure', () => post({ type: 'securityfailure' }));
        rfb.addEventListener('credentialsrequired', () => post({ type: 'securityfailure' }));
        rfb.addEventListener('desktopname', (e) => post({ type: 'title', title: String(e.detail.name || '').slice(0, 60) }));
    },
    receive(base64) {
        if (channel && channel.onmessage) { channel.onmessage({ data: fromBase64(base64) }); }
    },
    remoteClosed() {
        if (!channel || channel.readyState === 'closed') { return; }
        channel.readyState = 'closed';
        if (channel.onclose) { channel.onclose({ code: 1006, reason: '', wasClean: false }); }
    },
    setScale(scale) {
        if (!rfb) { return; }
        rfb.scaleViewport = scale;
        rfb.clipViewport = !scale;
    },
    showKeyboard() { keyboard.focus(); },
    hideKeyboard() { keyboard.blur(); },
    ctrlAltDel() { if (rfb) { rfb.sendCtrlAltDel(); } },
    key(name) {
        if (!rfb) { return; }
        const keys = {
            escape: [KeyTable.XK_Escape, 'Escape'], tab: [KeyTable.XK_Tab, 'Tab'],
            enter: [KeyTable.XK_Return, 'Enter'], up: [KeyTable.XK_Up, 'ArrowUp'],
            down: [KeyTable.XK_Down, 'ArrowDown'], left: [KeyTable.XK_Left, 'ArrowLeft'],
            right: [KeyTable.XK_Right, 'ArrowRight'],
        };
        const key = keys[name];
        if (key) { rfb.sendKey(key[0], key[1]); }
    },
    disconnect() { if (rfb) { rfb.disconnect(); } },
};

post({ type: 'ready' });
