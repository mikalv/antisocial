# Changelog

All notable changes to this project are documented here.

## [0.1.0] — 2026-05-01

Initial working release. Private 2-person chat app built with Elixir/Phoenix LiveView.

### Authentication & Sessions
- Password login
- One-time invite link (multiuse within 5-minute window for same link / different browser)
- Device code login (6-digit OTP, 15-minute TTL, generated from settings)
- Session management: list active sessions, revoke individual or all-other sessions
- **Passkeys (WebAuthn)** — register Face ID / Touch ID / security keys; login redirects through invite-token bridge so session creation is handled uniformly
- `mix antisocial.gen_invite USERNAME` — generate login link from server CLI

### Security & Privacy
- **PIN lock** — app locks after configurable idle timeout (2 / 5 / 10 / 30 min) or on tab hide
- **Calculator disguise** — when tab icon set to "Calculator", the PIN lock shows a fully functional iOS-style calculator; any expression whose result equals the PIN unlocks
- **Panic button** — double-click or Alt+Shift+X flushes the session and redirects; URL is replaced before lock overlay shows
- **Tab disguise** — change browser tab title + favicon to look like Google, calculator, notes, etc.
- **Keystroke timing profile** — records inter-keystroke intervals using Welford's online algorithm; builds a per-user typing baseline; anomaly z-score available for flagging unusual access

### Messaging
- Real-time chat via Phoenix PubSub + LiveView
- Typing indicators (debounced, auto-clear)
- Draft autosave (1.5 s debounce)
- Enter to send, Shift+Enter for newline
- Delete own messages (soft-archive)
- Long-press (mobile) / right-click (desktop) context menu
- Message TTL — set a self-destruct timer; message moves to a secret channel (or archives) after the recipient reads it
- Geolocation sharing — share GPS coordinates as a message

### Media
- Image attachments with 2-column grid layout for multiple images
- Video playback inline
- Audio playback inline (including voice messages)
- **Voice messages** — hold mic button to record via MediaRecorder API; injected into upload queue via DataTransfer; stored as `audio/webm`
- Uploaded media served at `/media/*` (authenticated only); stored under date-partitioned paths on disk

### Channels
- Public channels — visible in sidebar
- Secret channels — `pin_required: true`; hidden from sidebar, accessed by slug directly
- Create channel with public/secret toggle

### Calls
- **WebRTC audio/video calls** — peer-to-peer via RTCPeerConnection; signaling relayed over existing LiveView PubSub (`user:{id}` topics); STUN via `stun.l.google.com`
- In-call overlay: remote video full-screen, local preview PiP, mute / camera toggle / hang up

### Identity
- Gravatar as default avatar (identicon fallback — always renders, no broken images)
- Custom avatar upload (up to 5 MB image)
- Display name separate from username
- Contact aliases — rename contacts locally without affecting their account
- **Device fingerprinting** — canvas hash + UA + screen + timezone → stable `fp_id`; stored on `user_sessions.fingerprint` JSONB; shown in active-sessions list

### Settings
- Dark / light / system theme
- Notification mode: active (shows browser notification) or stealth (silent)
- Idle lock timeout selector
- PIN management (set, change, clear)
- Passkey management (add, remove)
- Tab disguise (icon + title)
- Contact aliases editor
- Avatar upload
- Device-code generator for logging in on another device
- Active sessions list with fingerprint IDs, last-seen timestamps, and per-session revoke
- **Hidden debug panel** — tap version string 5 times to reveal all channels (including secret), user count, and app version

### Infrastructure
- Docker Compose deployment (app + Postgres)
- IPv6 support on port 4481 behind reverse proxy
- `Antisocial.Release.migrate/0` for in-container migrations
- TTLWorker GenServer — polls every 30 s for expired TTL messages
- PasskeyChallenge GenServer — ETS-backed challenge cache with 5-minute TTL
