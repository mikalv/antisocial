# Antisocial — Chat App Design

**Date:** 2026-05-01
**Domain:** antisocial.rprxy.mdma.sh
**Stack:** Phoenix LiveView + PostgreSQL + disk media

---

## Overview

A private, invite-only 1-on-1 chat app for two people. Invite-only (admin creates accounts). Polished message composer with rich text, media support, and draft persistence. Designed with discretion as a first-class concern.

---

## Deployment

- Phoenix listens on `::` (IPv6 + IPv4) port **4481**
- rproxy handles TLS termination externally
- Docker Compose with uploads volume and embedded Postgres
- Secrets via `.env` file, never in git

**`config/runtime.exs`:**
```elixir
config :antisocial, AntisocialWeb.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 4481],
  url: [host: "antisocial.rprxy.mdma.sh", scheme: "https", port: 443],
  check_origin: false,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
```

**`docker-compose.yml`:**
```yaml
services:
  app:
    build: .
    ports:
      - "4481:4481"
    volumes:
      - ./uploads:/app/uploads
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      - DATABASE_URL
      - SECRET_KEY_BASE
      - PHX_HOST=antisocial.rprxy.mdma.sh
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD
```

`IDLE_LOCK_MINUTES` env-var controls auto-lock timeout (default: 10).

---

## Data Model

```sql
users
  id, username, hashed_password, pin_hash (nullable),
  notification_mode (enum: active | stealth),
  onboarded_at (nullable),
  inserted_at

channels
  id, slug (text unique),          -- "generelt", "kjemiprat", "minner", "hemmelig"
  name (text),                     -- display name, e.g. "#kjemiprat"
  pin_required (bool default false),
  inserted_at
  -- "generelt" channel is seeded automatically in priv/repo/seeds.exs (on_conflict: :nothing)
  -- pin_required channels: require PIN on entry AND never persist in nav/session
  -- navigate away → channel disappears from UI entirely, no trace
  -- re-entry: user types channel name in "join by name" input
  -- new channels = INSERT INTO channels, no code changes needed

messages
  id, user_id (FK), channel_id (FK),
  body (text), rich_body (jsonb),
  archived_at (nullable),         -- soft delete / hidden archive
  inserted_at

media_attachments
  id, message_id (FK), filename, original_filename,
  content_type, file_size, storage_path,
  inserted_at

drafts
  id, user_id (FK), channel_id (FK),
  body (text), rich_body (jsonb),
  updated_at
  -- one row per user per channel, upsert on change

bulletin_posts
  id, user_id (FK), body (text), pinned (bool default true),
  archived_at (nullable),
  inserted_at

notifications
  id, recipient_id (FK), read_at (nullable),
  inserted_at
  -- no link to message content, only "something happened"

invite_tokens
  id, user_id (FK), token (text unique),
  used_at (nullable), expires_at,
  inserted_at
```

Main chat view filters `WHERE archived_at IS NULL`.
Archive view requires PIN, shows `WHERE archived_at IS NOT NULL`.
`rich_body` JSONB holds formatting data; plain `body` used for notifications/search.

---

## Routes

```
/                     → redirect → /chat/generelt
/login                → SessionLive
/invite/:token        → InviteLive          (magic link, one-time)
/chat/:channel        → ChatLive            (all channels, same LiveView)
/bulletin             → BulletinLive        (shared pinboard)
```

No special routes for secret channels — they're just slugs. `/hemmelig` convenience redirect removed; users navigate via "join by name" input.

**Channel navigation model:**
- Normal channels (`pin_required: false`): appear in sidebar nav, persist across sessions
- Secret channels (`pin_required: true`): visible in sidebar **only while actively viewing**; navigate away → removed from nav immediately; no trace in session, localStorage, or history
- Re-entry to secret channel: "join by name" input (small text field, always available)

**Two-factor channel security for `pin_required` channels:**
1. You must know the channel slug (obscurity)
2. You must enter the correct PIN

Both are required. Knowing the slug alone is not enough.

---

## LiveView Architecture

**ChatLive / HemmeligLive** contain three LiveComponents:
- `MessageListComponent` — infinite scroll upward, streams new messages
- `ComposerComponent` — rich editor, autosave, media upload
- `NotificationBadgeComponent` — count only, no content

**BulletinLive** — shared pinboard, post + archive bulletin items.

**PIN lock** — overlay rendered when `current_user.pin_hash` is set and session is locked. Cannot be dismissed without correct PIN. On lock, URL is replaced with `/chat` via `history.replaceState` before overlay appears, hiding any trace of `/hemmelig`.

**Auto-lock triggers:**
- Tab hidden (Page Visibility API) for > `IDLE_LOCK_MINUTES`
- No user interaction for > `IDLE_LOCK_MINUTES`
- Tab/window reopened after absence

**Notification mode toggle — always visible banner:**
```
Varsler:  ● Aktiv  ○ Stille
```
Single `phx-click`, saved to DB immediately. Never buried in settings.

---

## Message Composer

```
┌─────────────────────────────────────────┐
│ [B] [I] [</>] [📎] [📷]      [● Aktiv] │  toolbar
├─────────────────────────────────────────┤
│                                         │
│  Skriv noe...                           │  contenteditable (Tiptap/ProseMirror)
│                                         │
├─────────────────────────────────────────┤
│ [bilde preview ×]              [Send ↵] │
└─────────────────────────────────────────┘
```

- `contenteditable` via Tiptap or ProseMirror for rich text
- Paste image directly → auto-upload begins
- Drag-and-drop anywhere on chat surface (desktop)
- Ctrl+Enter (desktop) / Send button (mobile)
- Draft autosaves every ~2s via debounced `phx-change` → upsert `drafts` table
- On reconnect: draft loaded from DB immediately — no loss on refresh/crash

---

## Media Upload Flow

```
User selects / pastes file
       ↓
Client-side validation (type check, max 200MB)
       ↓
Phoenix LiveView chunked upload (allow_upload/3)
  — progress bar in composer
       ↓
Server receives → saves to /app/uploads/YYYY/MM/DD/UUID-originalname
       ↓
Creates media_attachments row
       ↓
PubSub broadcasts message + media to all connected clients
       ↓
Inline preview:
  image → <img> with lazy loading
  video → <video controls preload="metadata">
```

Upload folder mounted as Docker volume `./uploads:/app/uploads` — survives container restarts.
No resize/compression now, but `storage_path` + `content_type` are ready for ImageMagick/FFmpeg later.

---

## Notifications

- Push notifications (Web Push API) + visual tab badge in **Aktiv** mode
- Nothing in **Stille** mode
- Notification text: **"1 ny notification"** — no message content, no sender name, nothing else
- Badge shows unread count only
- Read on chat open

---

## Magic Link / Invite

```
https://antisocial.rprxy.mdma.sh/invite/TOKEN
```

- 32-byte URL-safe random token
- Stored with `expires_at` (7 days)
- On click: auto-login, force password change, show onboarding modal
- Token invalidated after use (`used_at` set)
- Generated via `mix antisocial.create_user USERNAME`

---

## Onboarding Modal

Shown once after first login (`onboarded_at IS NULL`), then `onboarded_at` is set.

Explains:
1. Normal chat at `/chat`
2. Hidden chat exists at `/hemmelig` (PIN-protected, not linked anywhere)
3. Notification toggle banner — always visible at top
4. PIN setup (optional, recommended)

---

## Privacy & Discretion Summary

| Concern | Solution |
|---------|----------|
| Hidden chat discovery | `/hemmelig` never linked in UI |
| URL leak when locked | `history.replaceState("/chat")` before PIN overlay |
| Notification content | Only count shown, never text or sender |
| Auto-lock | Page Visibility API + idle timer |
| Archived messages | Soft delete, PIN required to view |
| Invite link | Short-lived token, safe for SMS |

---

## Mobile

- Responsive layout, composer stacks vertically on small screens
- Send button prominent on mobile (Ctrl+Enter hint hidden)
- Notification banner always reachable without scrolling
- Touch-friendly tap targets throughout
