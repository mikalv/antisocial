// ─── Theme ────────────────────────────────────────────────────────────────────

export const ThemeHook = {
  mounted() {
    const saved = localStorage.getItem("theme") || this.el.dataset.theme || "system"
    applyTheme(saved)
  },

  updated() {
    const theme = this.el.dataset.theme
    if (theme) {
      localStorage.setItem("theme", theme)
      applyTheme(theme)
    }
  }
}

function applyTheme(theme) {
  const root = document.documentElement
  if (theme === "dark" || (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches)) {
    root.classList.add("dark")
  } else {
    root.classList.remove("dark")
  }
}

// Handle replace_url events from LiveView (used by panic button)
window.addEventListener("phx:replace_url", (e) => {
  history.replaceState(null, "", e.detail.url)
})

// Apply theme immediately on page load (before LiveView mounts) to avoid flash
const storedTheme = localStorage.getItem("theme") || "system"
applyTheme(storedTheme)

// ─── PIN Lock ─────────────────────────────────────────────────────────────────

export const PinLock = {
  idleTimer: null,
  idleMinutes: 10,

  mounted() {
    this.idleMinutes = parseInt(this.el.dataset.idleMinutes || "10")
    this.setupIdleTimer()
    this.setupVisibilityLock()
  },

  destroyed() {
    clearTimeout(this.idleTimer)
    document.removeEventListener("visibilitychange", this._visibilityHandler)
  },

  setupIdleTimer() {
    const events = ["mousedown", "mousemove", "keydown", "touchstart", "scroll"]
    const reset = () => {
      clearTimeout(this.idleTimer)
      this.idleTimer = setTimeout(() => this.lock(), this.idleMinutes * 60 * 1000)
    }
    events.forEach(e => document.addEventListener(e, reset, { passive: true }))
    reset()
  },

  setupVisibilityLock() {
    let hiddenAt = null
    this._visibilityHandler = () => {
      if (document.hidden) {
        hiddenAt = Date.now()
      } else if (hiddenAt) {
        const elapsed = (Date.now() - hiddenAt) / 1000 / 60
        if (elapsed >= this.idleMinutes) this.lock()
        hiddenAt = null
      }
    }
    document.addEventListener("visibilitychange", this._visibilityHandler)
  },

  lock() {
    // Replace URL before showing lock overlay — hides /hemmelig from address bar
    if (window.location.pathname !== "/chat/generelt") {
      history.replaceState(null, "", "/chat/generelt")
    }
    this.pushEvent("lock", {})
  }
}

// ─── Auto-scroll chat ─────────────────────────────────────────────────────────

export const ScrollBottom = {
  mounted() { this.scrollToBottom() },
  updated() {
    // Only auto-scroll if already near bottom
    const el = this.el
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 120
    if (nearBottom) this.scrollToBottom()
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

// ─── Composer (draft autosave + typing indicator + Enter-to-send) ─────────────

export const ComposerHook = {
  mounted() {
    this.draftTimer = null
    this.typingTimer = null
    this.isTyping = false
    this._ksIntervals = []
    this._ksLastKey = null

    this.el.addEventListener("input", () => {
      // Draft autosave
      clearTimeout(this.draftTimer)
      this.draftTimer = setTimeout(() => {
        this.pushEvent("save_draft", { body: this.el.value })
      }, 1500)

      // Typing indicator
      if (!this.isTyping) {
        this.isTyping = true
        this.pushEvent("typing_start", {})
      }
      clearTimeout(this.typingTimer)
      this.typingTimer = setTimeout(() => {
        this.isTyping = false
        this.pushEvent("typing_stop", {})
      }, 2000)
    })

    this.el.addEventListener("keydown", (e) => {
      // Keystroke timing
      const now = performance.now()
      if (this._ksLastKey !== null) {
        const interval = now - this._ksLastKey
        if (interval >= 20 && interval <= 2000) {
          this._ksIntervals.push(Math.round(interval))
        }
      }
      this._ksLastKey = now

      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        // Flush keystroke sample before submitting
        if (this._ksIntervals.length >= 3) {
          this.pushEvent("keystroke_sample", { intervals: this._ksIntervals.slice() })
        }
        this._ksIntervals = []
        this._ksLastKey = null
        const form = this.el.closest("form")
        if (form) form.requestSubmit()
      }
    })
  },

  destroyed() {
    clearTimeout(this.draftTimer)
    clearTimeout(this.typingTimer)
    if (this.isTyping) this.pushEvent("typing_stop", {})
  }
}

// Keep old names as aliases for backward compat
export const DraftAutosave = ComposerHook
export const TypingIndicator = ComposerHook

// ─── Tab disguise ─────────────────────────────────────────────────────────────

export const TabDisguise = {
  mounted() {
    const title = this.el.dataset.title
    const icon = this.el.dataset.icon
    if (title) document.title = title
    if (icon) {
      const link = document.querySelector("link[rel~='icon']") || document.createElement("link")
      link.rel = "icon"
      link.href = `/icons/${icon}`
      document.head.appendChild(link)
    }
  }
}

// ─── Panic button ─────────────────────────────────────────────────────────────
// Triggers: double-click on element OR Alt+Shift+X anywhere on page

export const PanicButton = {
  mounted() {
    // Double-click trigger
    let clicks = 0
    this.el.addEventListener("click", () => {
      clicks++
      if (clicks === 2) {
        clicks = 0
        this.pushEvent("panic", {})
      }
      setTimeout(() => { clicks = 0 }, 400)
    })

    // Keyboard shortcut: Alt+Shift+X
    this._keyHandler = (e) => {
      if (e.altKey && e.shiftKey && e.key === "X") {
        e.preventDefault()
        this.pushEvent("panic", {})
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  },

  destroyed() {
    document.removeEventListener("keydown", this._keyHandler)
  }
}

// ─── Media upload progress ────────────────────────────────────────────────────

export const UploadProgress = {
  mounted() {
    this.handleEvent("upload_progress", ({ progress }) => {
      this.el.style.width = `${progress}%`
    })
  }
}

// ─── Browser notifications + geolocation ──────────────────────────────────────

export const Notifications = {
  mounted() {
    this.handleEvent("request_notification_permission", () => {
      if ("Notification" in window && Notification.permission === "default") {
        Notification.requestPermission()
      }
    })

    this.handleEvent("show_notification", ({ title, body }) => {
      if ("Notification" in window && Notification.permission === "granted") {
        new Notification(title, { body, icon: "/icons/bubbles_chat.svg", silent: true })
      }
    })

    this.handleEvent("request_geo", () => {
      if (!navigator.geolocation) return
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          this.pushEvent("share_location", {
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
            accuracy: Math.round(pos.coords.accuracy)
          })
        },
        (_err) => {},
        { timeout: 15000, maximumAge: 60000 }
      )
    })
  }
}

// ─── Device fingerprint ───────────────────────────────────────────────────────
// Collects browser/device signals, hashes them to a stable ID, and pushes
// to the server once per session. Stored on the user_session row.

export const DeviceFingerprint = {
  mounted() {
    this._collect().then(fp => this.pushEvent("store_fingerprint", fp))
  },

  async _collect() {
    const nav = navigator
    const scr = screen

    // Canvas fingerprint
    let canvasHash = ""
    try {
      const canvas = document.createElement("canvas")
      const ctx = canvas.getContext("2d")
      ctx.textBaseline = "top"
      ctx.font = "14px 'Arial'"
      ctx.fillStyle = "#f60"
      ctx.fillRect(125, 1, 62, 20)
      ctx.fillStyle = "#069"
      ctx.fillText("antisocial🔒", 2, 15)
      ctx.fillStyle = "rgba(102,204,0,0.7)"
      ctx.fillText("antisocial🔒", 4, 17)
      canvasHash = btoa(canvas.toDataURL()).slice(0, 32)
    } catch (_) {}

    const signals = {
      ua: nav.userAgent,
      lang: nav.language,
      langs: (nav.languages || []).join(","),
      tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      screen: `${scr.width}x${scr.height}x${scr.colorDepth}`,
      dpr: window.devicePixelRatio,
      cores: nav.hardwareConcurrency,
      mem: nav.deviceMemory || null,
      touch: nav.maxTouchPoints,
      platform: nav.platform || null,
      canvas: canvasHash,
      plugins: Array.from(nav.plugins || []).map(p => p.name).join(","),
      do_not_track: nav.doNotTrack,
    }

    // Stable hash ID from all signals combined
    const raw = Object.values(signals).join("|")
    const encoded = btoa(unescape(encodeURIComponent(raw)))
    let hash = 0
    for (let i = 0; i < encoded.length; i++) {
      hash = ((hash << 5) - hash) + encoded.charCodeAt(i)
      hash |= 0
    }
    signals.fp_id = Math.abs(hash).toString(16).padStart(8, "0")

    return signals
  }
}

// ─── Voice recorder ───────────────────────────────────────────────────────────
// Hold mic button to record, release to send. Uses MediaRecorder API.
// On stop, creates a File and injects it into the LiveView upload queue
// so the normal send_with_media flow handles it.

export const VoiceRecorder = {
  mounted() {
    this.mediaRecorder = null
    this.chunks = []
    this.stream = null

    const btn = this.el
    btn.addEventListener("mousedown",  (e) => { e.preventDefault(); this._start() })
    btn.addEventListener("touchstart", (e) => { e.preventDefault(); this._start() }, { passive: false })
    btn.addEventListener("mouseup",    () => this._stop())
    btn.addEventListener("mouseleave", () => { if (this.mediaRecorder?.state === "recording") this._stop() })
    btn.addEventListener("touchend",   () => this._stop())
  },

  destroyed() {
    this._cleanup()
  },

  async _start() {
    if (this.mediaRecorder) return
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.chunks = []
      this.mediaRecorder = new MediaRecorder(this.stream)
      this.mediaRecorder.ondataavailable = (e) => { if (e.data.size > 0) this.chunks.push(e.data) }
      this.mediaRecorder.onstop = () => this._onStop()
      this.mediaRecorder.start()
      this.el.classList.add("text-red-500")
      this.pushEvent("recording_started", {})
    } catch (_) {
      // Mic permission denied — ignore
    }
  },

  _stop() {
    if (this.mediaRecorder?.state === "recording") {
      this.mediaRecorder.stop()
    }
    this.el.classList.remove("text-red-500")
  },

  _onStop() {
    const blob = new Blob(this.chunks, { type: "audio/webm" })
    const file = new File([blob], `voice-${Date.now()}.webm`, { type: "audio/webm" })

    // Inject into the LiveView upload input so the normal upload flow picks it up
    const input = document.querySelector("input[data-phx-upload-ref]")
    if (input) {
      const dt = new DataTransfer()
      dt.items.add(file)
      input.files = dt.files
      input.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this._cleanup()
    this.pushEvent("recording_stopped", {})
  },

  _cleanup() {
    this.mediaRecorder = null
    this.chunks = []
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
  }
}

// ─── Calculator PIN lock ──────────────────────────────────────────────────────
// Looks like a real calculator. Pressing = evaluates the expression;
// if the numeric result matches the PIN the server unlocks — otherwise it just
// shows the result, exactly like a normal calculator app.

export const CalculatorLock = {
  mounted() {
    this.state = { display: "0", expr: "", operand: null, operator: null, justEvaled: false }
    this._render()

    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-action]")
      if (btn) this._handle(btn.dataset.action)
    })
  },

  _render() {
    const d = this.el.querySelector("#calc-display")
    const ex = this.el.querySelector("#calc-expr")
    if (d) d.textContent = this.state.display
    if (ex) ex.textContent = this.state.expr
  },

  _handle(action) {
    const s = this.state
    if (action === "ac") {
      this.state = { display: "0", expr: "", operand: null, operator: null, justEvaled: false }
    } else if (action.startsWith("digit:")) {
      const d = action.split(":")[1]
      if (s.justEvaled) {
        this.state = { ...s, display: d, expr: "", justEvaled: false }
      } else {
        this.state = { ...s, display: s.display === "0" ? d : s.display + d, justEvaled: false }
      }
    } else if (action === "dot") {
      if (!s.display.includes(".")) {
        this.state = { ...s, display: s.display + ".", justEvaled: false }
      }
    } else if (action === "sign") {
      const n = parseFloat(s.display) * -1
      this.state = { ...s, display: String(n) }
    } else if (action === "pct") {
      const n = parseFloat(s.display) / 100
      this.state = { ...s, display: String(n) }
    } else if (action.startsWith("op:")) {
      const op = action.split(":")[1]
      const opLabel = { "/": "÷", "*": "×", "-": "−", "+": "+" }[op] || op
      this.state = {
        display: s.display,
        expr: s.display + " " + opLabel,
        operand: parseFloat(s.display),
        operator: op,
        justEvaled: false
      }
    } else if (action === "equals") {
      if (s.operator && s.operand !== null) {
        const a = s.operand, b = parseFloat(s.display)
        let result
        switch (s.operator) {
          case "+": result = a + b; break
          case "-": result = a - b; break
          case "*": result = a * b; break
          case "/": result = b !== 0 ? a / b : "Error"; break
          default: result = b
        }
        const resultStr = result === "Error" ? "Error" : String(Number.isInteger(result) ? result : parseFloat(result.toFixed(10)))
        this.state = { display: resultStr, expr: "", operand: null, operator: null, justEvaled: true }

        // Attempt PIN verification with the result
        if (result !== "Error") {
          const pinInput = document.getElementById("calc-pin-input")
          const form = document.getElementById("calc-form")
          if (pinInput && form) {
            pinInput.value = resultStr
            // Small delay so display updates first — makes it look natural
            setTimeout(() => form.requestSubmit(), 120)
          }
        }
      }
    }
    this._render()
  }
}

// ─── WebRTC audio/video calls ──────────────────────────────────────────────────
// Signaling is relayed through LiveView PubSub. All overlay DOM is built with
// safe createElement/textContent — no innerHTML with user data.

const _ICE = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
]

function _el(tag, css, text) {
  const e = document.createElement(tag)
  if (css) e.style.cssText = css
  if (text !== undefined) e.textContent = text
  return e
}

export const WebRTCHook = {
  _pc: null,
  _localStream: null,
  _remoteUserId: null,
  _overlay: null,
  _pendingIce: [],

  mounted() {
    this.handleEvent("webrtc_ring", ({ from_id, from_name }) => {
      this._remoteUserId = from_id
      this._showRinging(from_name)
    })
    this.handleEvent("webrtc_accepted", () => {
      this._showConnecting()
      this._startAsCallerAsync()
    })
    this.handleEvent("webrtc_offer", ({ sdp, from_id }) => {
      this._remoteUserId = from_id
      this._handleOfferAsync(sdp)
    })
    this.handleEvent("webrtc_answer", ({ sdp }) => { this._handleAnswerAsync(sdp) })
    this.handleEvent("webrtc_ice",    ({ candidate }) => { this._handleIceAsync(candidate) })
    this.handleEvent("webrtc_hangup", () => { this._cleanup(); this._removeOverlay() })
  },

  async _startAsCallerAsync() {
    try {
      this._localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      this._setupPC()
      this._localStream.getTracks().forEach(t => this._pc.addTrack(t, this._localStream))
      const offer = await this._pc.createOffer()
      await this._pc.setLocalDescription(offer)
      this.pushEvent("webrtc_offer", { sdp: { type: offer.type, sdp: offer.sdp }, to: String(this._remoteUserId) })
    } catch(_) { this._cleanup(); this._removeOverlay() }
  },

  async _handleOfferAsync(sdp) {
    try {
      this._localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      this._setupPC()
      this._localStream.getTracks().forEach(t => this._pc.addTrack(t, this._localStream))
      await this._pc.setRemoteDescription(new RTCSessionDescription(sdp))
      for (const c of this._pendingIce) await this._pc.addIceCandidate(new RTCIceCandidate(c)).catch(()=>{})
      this._pendingIce = []
      const answer = await this._pc.createAnswer()
      await this._pc.setLocalDescription(answer)
      this.pushEvent("webrtc_answer", { sdp: { type: answer.type, sdp: answer.sdp }, to: String(this._remoteUserId) })
      this._showInCall()
    } catch(_) { this._cleanup(); this._removeOverlay() }
  },

  async _handleAnswerAsync(sdp) {
    if (!this._pc) return
    try {
      await this._pc.setRemoteDescription(new RTCSessionDescription(sdp))
      for (const c of this._pendingIce) await this._pc.addIceCandidate(new RTCIceCandidate(c)).catch(()=>{})
      this._pendingIce = []
      this._showInCall()
    } catch(_) {}
  },

  async _handleIceAsync(c) {
    if (this._pc && this._pc.remoteDescription) {
      await this._pc.addIceCandidate(new RTCIceCandidate(c)).catch(()=>{})
    } else {
      this._pendingIce.push(c)
    }
  },

  _setupPC() {
    this._pc = new RTCPeerConnection({ iceServers: _ICE })
    this._pc.onicecandidate = ({ candidate }) => {
      if (candidate) this.pushEvent("webrtc_ice", { candidate: candidate.toJSON(), to: String(this._remoteUserId) })
    }
    this._pc.ontrack = ({ streams }) => {
      const rv = document.getElementById("call-remote-video")
      if (rv && streams[0]) { rv.srcObject = streams[0]; rv.play().catch(()=>{}) }
    }
    this._pc.onconnectionstatechange = () => {
      const s = this._pc?.connectionState
      if (s === "disconnected" || s === "failed" || s === "closed") {
        this.pushEvent("webrtc_hangup", { to: String(this._remoteUserId) })
        this._cleanup(); this._removeOverlay()
      }
    }
  },

  _createOverlay() {
    this._removeOverlay()
    const div = _el("div", "position:fixed;inset:0;z-index:9999;background:#111827;display:flex;flex-direction:column;align-items:center;justify-content:center;")
    div.id = "call-overlay"
    document.body.appendChild(div)
    this._overlay = div
    return div
  },
  _removeOverlay() { document.getElementById("call-overlay")?.remove(); this._overlay = null },

  _showRinging(fromName) {
    const ov = this._createOverlay()
    const name = _el("div", "color:#fff;font-size:1.4rem;font-weight:300;margin-bottom:.4rem")
    name.textContent = fromName  // safe: textContent only
    const sub  = _el("div", "color:#9ca3af;font-size:.85rem;margin-bottom:2rem")
    sub.textContent = "Incoming call…"
    const row  = _el("div", "display:flex;gap:2.5rem")
    const dec  = _el("button", "width:64px;height:64px;border-radius:50%;background:#ef4444;border:none;color:#fff;font-size:1.5rem;cursor:pointer", "✕")
    const acc  = _el("button", "width:64px;height:64px;border-radius:50%;background:#22c55e;border:none;color:#fff;font-size:1.5rem;cursor:pointer", "✓")
    dec.onclick = () => { this.pushEvent("webrtc_hangup", { to: String(this._remoteUserId) }); this._cleanup(); this._removeOverlay() }
    acc.onclick = () => { this.pushEvent("webrtc_accept_call", { to: String(this._remoteUserId) }); this._showConnecting() }
    row.append(dec, acc)
    ov.append(name, sub, row)
  },

  _showConnecting() {
    const ov = this._overlay || this._createOverlay()
    while (ov.firstChild) ov.removeChild(ov.firstChild)
    ov.append(
      _el("div", "color:#fff;font-size:1.2rem;font-weight:300;margin-bottom:1.5rem", "Connecting…"),
    )
    const cancel = _el("button", "margin-top:2rem;width:56px;height:56px;border-radius:50%;background:#ef4444;border:none;color:#fff;font-size:1.4rem;cursor:pointer", "✕")
    cancel.onclick = () => { this.pushEvent("webrtc_hangup", { to: String(this._remoteUserId) }); this._cleanup(); this._removeOverlay() }
    ov.append(cancel)
  },

  _showInCall() {
    const ov = this._overlay || this._createOverlay()
    while (ov.firstChild) ov.removeChild(ov.firstChild)
    ov.style.position = "fixed"

    const remVid = document.createElement("video")
    remVid.id = "call-remote-video"
    remVid.autoplay = true; remVid.playsInline = true
    remVid.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:#000"

    const locVid = document.createElement("video")
    locVid.id = "call-local-video"
    locVid.autoplay = true; locVid.playsInline = true; locVid.muted = true
    locVid.style.cssText = "position:absolute;bottom:1.5rem;right:1.5rem;width:140px;height:105px;object-fit:cover;border-radius:12px;border:2px solid #374151;z-index:10;background:#111"
    if (this._localStream) { locVid.srcObject = this._localStream; locVid.play().catch(()=>{}) }

    const controls = _el("div", "position:absolute;bottom:2rem;left:50%;transform:translateX(-50%);display:flex;gap:1.25rem;z-index:20")
    let audioMuted = false, camOff = false

    const muteBtn = _el("button", "width:48px;height:48px;border-radius:50%;background:#374151;border:none;color:#fff;font-size:1.2rem;cursor:pointer", "🎤")
    muteBtn.title = "Mute"
    muteBtn.onclick = () => {
      audioMuted = !audioMuted
      this._localStream?.getAudioTracks().forEach(t => { t.enabled = !audioMuted })
      muteBtn.textContent = audioMuted ? "🔇" : "🎤"
    }

    const camBtn = _el("button", "width:48px;height:48px;border-radius:50%;background:#374151;border:none;color:#fff;font-size:1.2rem;cursor:pointer", "📷")
    camBtn.title = "Camera"
    camBtn.onclick = () => {
      camOff = !camOff
      this._localStream?.getVideoTracks().forEach(t => { t.enabled = !camOff })
      camBtn.textContent = camOff ? "🚫" : "📷"
    }

    const hangBtn = _el("button", "width:56px;height:56px;border-radius:50%;background:#ef4444;border:none;color:#fff;font-size:1.4rem;cursor:pointer", "✕")
    hangBtn.title = "Hang up"
    hangBtn.onclick = () => { this.pushEvent("webrtc_hangup", { to: String(this._remoteUserId) }); this._cleanup(); this._removeOverlay() }

    controls.append(muteBtn, camBtn, hangBtn)
    ov.append(remVid, locVid, controls)
  },

  _cleanup() {
    this._pc?.close(); this._pc = null
    this._localStream?.getTracks().forEach(t => t.stop()); this._localStream = null
    this._remoteUserId = null
    this._pendingIce = []
  },

  destroyed() { this._cleanup(); this._removeOverlay() }
}

// ─── Passkey registration (settings LiveView) ─────────────────────────────────
// Fetches a registration challenge, calls navigator.credentials.create(),
// posts the attestation, then fires a LiveView event to refresh the list.

export const PasskeyRegister = {
  mounted() {
    const btn = document.getElementById("add-passkey-btn")
    if (!btn) return
    btn.addEventListener("click", () => this._register())
  },

  async _register() {
    try {
      const challengeRes = await fetch("/passkeys/register/challenge", {
        headers: { accept: "application/json", "x-csrf-token": _csrfToken() }
      })
      if (!challengeRes.ok) throw new Error("challenge failed")
      const opts = await challengeRes.json()

      // Decode base64url fields expected as ArrayBuffers by WebAuthn
      const publicKey = {
        ...opts,
        challenge: _b64ToBuffer(opts.challenge),
        user: { ...opts.user, id: _b64ToBuffer(opts.user.id) },
        excludeCredentials: (opts.excludeCredentials || []).map(c => ({
          ...c, id: _b64ToBuffer(c.id)
        }))
      }

      const cred = await navigator.credentials.create({ publicKey })
      const payload = {
        id: cred.id,
        rawId: _bufToB64(cred.rawId),
        type: cred.type,
        response: {
          attestationObject: _bufToB64(cred.response.attestationObject),
          clientDataJSON: _bufToB64(cred.response.clientDataJSON)
        }
      }

      const regRes = await fetch("/passkeys/register", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": _csrfToken()
        },
        body: JSON.stringify(payload)
      })
      const result = await regRes.json()
      if (result.ok) {
        this.pushEvent("passkey_registered", {})
      } else {
        this.pushEvent("passkey_error", { message: result.error || "registration failed" })
      }
    } catch (err) {
      if (err.name !== "NotAllowedError") {
        this.pushEvent("passkey_error", { message: err.message || "passkey error" })
      }
    }
  }
}

// ─── Passkey authentication (plain login page — no LiveView) ───────────────────
// Runs on DOMContentLoaded. Fetches challenge, calls navigator.credentials.get(),
// posts the assertion, then follows the redirect URL returned by the server.

function _initPasskeyAuth() {
  const btn = document.getElementById("passkey-auth-btn")
  const errEl = document.getElementById("passkey-auth-error")
  if (!btn) return

  btn.addEventListener("click", async () => {
    const username = (document.getElementById("passkey-username-hint")?.value || "").trim()
    if (errEl) errEl.classList.add("hidden")
    try {
      const params = username ? `?username=${encodeURIComponent(username)}` : ""
      const challengeRes = await fetch(`/passkeys/auth/challenge${params}`, {
        headers: { accept: "application/json", "x-csrf-token": _csrfToken() }
      })
      if (!challengeRes.ok) throw new Error("challenge failed")
      const opts = await challengeRes.json()

      const publicKey = {
        challenge: _b64ToBuffer(opts.challenge),
        rpId: opts.rpId,
        userVerification: opts.userVerification || "preferred",
        timeout: opts.timeout || 60000,
        allowCredentials: (opts.allowCredentials || []).map(c => ({
          ...c, id: _b64ToBuffer(c.id)
        }))
      }

      const cred = await navigator.credentials.get({ publicKey })
      const payload = {
        id: cred.id,
        rawId: _bufToB64(cred.rawId),
        type: cred.type,
        response: {
          authenticatorData: _bufToB64(cred.response.authenticatorData),
          clientDataJSON: _bufToB64(cred.response.clientDataJSON),
          signature: _bufToB64(cred.response.signature),
          userHandle: cred.response.userHandle ? _bufToB64(cred.response.userHandle) : null
        }
      }

      const authRes = await fetch("/passkeys/auth", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": _csrfToken()
        },
        body: JSON.stringify(payload)
      })
      const result = await authRes.json()
      if (result.redirect) {
        window.location.href = result.redirect
      } else {
        if (errEl) { errEl.textContent = result.error || "auth failed"; errEl.classList.remove("hidden") }
      }
    } catch (err) {
      if (err.name !== "NotAllowedError" && errEl) {
        errEl.textContent = err.message || "passkey error"
        errEl.classList.remove("hidden")
      }
    }
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", _initPasskeyAuth)
} else {
  _initPasskeyAuth()
}

// ─── Shared WebAuthn helpers ───────────────────────────────────────────────────

function _b64ToBuffer(b64url) {
  const b64 = b64url.replace(/-/g, "+").replace(/_/g, "/")
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4))
  const raw = atob(b64 + pad)
  const buf = new ArrayBuffer(raw.length)
  const view = new Uint8Array(buf)
  for (let i = 0; i < raw.length; i++) view[i] = raw.charCodeAt(i)
  return buf
}

function _bufToB64(buf) {
  const bytes = new Uint8Array(buf)
  let str = ""
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
}

function _csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

// ─── Keystroke timing (extends ComposerHook) ───────────────────────────────────
// Collects inter-keystroke intervals; pushes a sample to the server after send.

export const KeystrokeCollector = {
  _intervals: [],
  _lastKey: null,

  mounted() {
    this.el.addEventListener("keydown", (e) => {
      const now = performance.now()
      if (this._lastKey !== null) {
        const interval = now - this._lastKey
        // Only collect plausible typing intervals (20ms–2000ms)
        if (interval >= 20 && interval <= 2000) {
          this._intervals.push(Math.round(interval))
        }
      }
      this._lastKey = now
    })
  },

  flush() {
    if (this._intervals.length >= 3) {
      this.pushEvent("keystroke_sample", { intervals: this._intervals.slice() })
    }
    this._intervals = []
    this._lastKey = null
  },

  destroyed() {
    this._intervals = []
    this._lastKey = null
  }
}

// ─── Message long-press / right-click context menu ────────────────────────────
// Triggers "show_message_menu" with { id } back to LiveView

export const MessageContext = {
  mounted() {
    let timer = null

    // Long-press (mobile)
    this.el.addEventListener("touchstart", (e) => {
      timer = setTimeout(() => {
        timer = null
        this.pushEvent("show_message_menu", { id: this.el.dataset.msgId })
      }, 500)
    }, { passive: true })

    this.el.addEventListener("touchend", () => {
      if (timer) { clearTimeout(timer); timer = null }
    }, { passive: true })

    this.el.addEventListener("touchmove", () => {
      if (timer) { clearTimeout(timer); timer = null }
    }, { passive: true })

    // Right-click (desktop)
    this.el.addEventListener("contextmenu", (e) => {
      e.preventDefault()
      this.pushEvent("show_message_menu", { id: this.el.dataset.msgId })
    })
  }
}
