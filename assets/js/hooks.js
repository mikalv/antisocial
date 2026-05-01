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

// ─── Draft autosave ───────────────────────────────────────────────────────────

export const DraftAutosave = {
  mounted() {
    this.timer = null
    this.el.addEventListener("input", () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => {
        this.pushEvent("save_draft", { body: this.el.value })
      }, 1500)
    })
  },
  destroyed() { clearTimeout(this.timer) }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

export const TypingIndicator = {
  mounted() {
    this.typingTimer = null
    this.isTyping = false
    this.el.addEventListener("input", () => {
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
  },
  destroyed() { clearTimeout(this.typingTimer) }
}

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

// ─── Media upload progress ────────────────────────────────────────────────────

export const UploadProgress = {
  mounted() {
    this.handleEvent("upload_progress", ({ progress }) => {
      this.el.style.width = `${progress}%`
    })
  }
}
