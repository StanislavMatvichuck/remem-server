# Remem Rooms server

Swift [Vapor](https://vapor.codes) server behind the Rooms feature of [Remem](https://github.com/StanislavMatvichuck/remem). Rooms let users share one event: every member gets the room event in their events list, each swipe is sent here, and other members receive a push notification unless they turned notifications off for that member.

## Run locally

```bash
swift run RoomsServer serve
```

Without `DATABASE_URL` the server uses a local SQLite file `rooms.sqlite`. Without APNs keys, notifications are only logged. The iOS app reads the server address from `RememRoomsServerURL` in `Application/Resources/Info.plist`. It points to the Railway deployment; change it to `http://localhost:8080` to use a local server with the simulator.

```bash
swift test
```

## Deploy on Railway

The server is a Railway service built from `Dockerfile` with settings from `railway.json`. Without a database, it falls back to a SQLite file inside the container, and that file is erased on every redeploy. Connect Postgres to keep users and rooms.

### 1. Service settings

Create the service from this repository. On the service open **Settings → Networking → Generate Domain**: room links use this domain automatically through `RAILWAY_PUBLIC_DOMAIN`.

Railway provides `PORT`, so don't set it.

### 2. Add Postgres

1. On the project canvas click **Create** and choose **Database → PostgreSQL**.
2. Wait until the new **Postgres** service is running. Railway fills in its variables; nothing needs configuring there.

### 3. Connect the server to Postgres

1. Open the server service and go to the **Variables** tab.
2. Click **New Variable**. Name it `DATABASE_URL` and set its value to `${{Postgres.DATABASE_URL}}`.
   `Postgres` is the database service name shown on the canvas. If you renamed that service, use the new name. Typing `${{` shows suggestions.
3. Railway stages variable changes. Click **Deploy** on the banner at the top of the canvas to apply them.
4. Open the new deployment and choose **View logs**. `Using Postgres at postgres.railway.internal` followed by `Database migrations are up to date` means the server uses Postgres. If you see `DATABASE_URL is not set, using local SQLite file`, the variable didn't apply. Production logs show `notice` level and above; set `LOG_LEVEL` to `info` to see each request and migration.

This reference uses Railway's private network (`postgres.railway.internal`), so the database needs no public access. That network is already encrypted, and Railway's Postgres certificate is self-signed, so the server connects without TLS on `*.railway.internal` hosts. Don't use `DATABASE_PUBLIC_URL` here: it goes over the internet and fails certificate verification.

### 4. Push notifications

Everything except push notifications works without this step; until then the server only logs them.

1. In Apple Developer go to **Certificates, IDs & Profiles → Keys** and add a key with **Apple Push Notifications service (APNs)** enabled. Configure it with environment **Sandbox & Production**: apps run from Xcode and simulators only accept sandbox pushes, TestFlight and App Store builds only production ones. If you restrict the key to a topic, choose `io.remem`. Download the `.p8` file (it can be downloaded only once) and note the **Key ID**. The **Team ID** is shown under **Membership**.
2. Copy the key as a single line with `\n` in place of line breaks. The file name contains the Key ID:

   ```bash
   awk '{printf "%s\\n", $0}' ~/Downloads/AuthKey_<Key ID>.p8 | pbcopy
   ```

3. Add these variables to the server service, then click **Deploy**:

   | Variable | Value |
   | --- | --- |
   | `APNS_KEY_ID` | Key ID |
   | `APNS_TEAM_ID` | Team ID |
   | `APNS_PRIVATE_KEY` | The copied single-line key |

4. The deployment logs show `APNS is configured for topic io.remem`.

The app reports with its device token whether it is a sandbox build (simulator or run from Xcode) or a production build (TestFlight or App Store), and the server sends through the matching environment. Tokens that APNs reports as no longer valid are removed.

Each swipe in a room logs one of:

- `push accepted by APNs for 1 of 1 devices`
- `push delivery failed: …` with the reason from Apple
- `push skipped for room …` with counts of muted members and members without a device token

### All variables

| Variable | Set by | Description |
| --- | --- | --- |
| `DATABASE_URL` | you | `${{Postgres.DATABASE_URL}}` |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` | you, for push | APNs auth key |
| `APNS_TOPIC` | you, optional | App bundle ID, default `io.remem` |
| `PUBLIC_URL` | you, optional | Base of room links when using a custom domain |
| `APP_URL_SCHEME` | you, optional | Scheme that join links open, default `remem` |
| `AUTO_MIGRATE` | you, optional | `false` disables migrations at startup |
| `LOG_LEVEL` | you, optional | `info` or `debug` for more detailed logs, default `notice` in production |
| `PORT`, `RAILWAY_PUBLIC_DOMAIN` | Railway | Provided automatically |

## API

All bodies are JSON, and dates are ISO 8601. Every `/v1` endpoint except registration requires `Authorization: Bearer <token>`.

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| `GET` | `/health` | | `ok` |
| `POST` | `/v1/users` | `{name, color}` | `201 {user, token}`, token is shown once and stored hashed |
| `PATCH` | `/v1/users/me` | `{name?, color?, deviceToken?, deviceEnvironment?}` | `User`; `deviceEnvironment` is `sandbox` (default) or `production` |
| `GET` | `/v1/rooms` | | `[Room]` of the current user |
| `POST` | `/v1/rooms` | `{name, eventName}` | `201 Room`, creator becomes the first member |
| `GET` | `/v1/rooms/:roomId` | | `Room`, members only |
| `POST` | `/v1/rooms/:roomId/members` | | `Room`, joins the room, repeated calls are ignored |
| `DELETE` | `/v1/rooms/:roomId/members/me` | | `204`, leaves the room and removes the user's swipes and mutes in it; a room without members is deleted |
| `POST` | `/v1/rooms/:roomId/happenings` | `{id, dateCreated}` | `Room`, records a swipe and notifies members; `id` makes it idempotent |
| `PUT` | `/v1/rooms/:roomId/members/:userId/notifications` | `{enabled}` | `Room`, turns notifications about that member on or off for the current user |
| `GET` | `/join/:roomId` | | HTML page that opens `remem://rooms/join/<roomId>` |

```jsonc
// Room
{
  "id": "UUID",
  "name": "Gym",
  "eventName": "Pull-ups",
  "link": "https://<domain>/join/<id>",
  "members": [{
    "id": "UUID",
    "name": "Alice",
    "color": "#34C759",
    "happeningsCount": 3,
    "lastHappeningDate": "2026-10-27T10:00:00Z",
    "notificationsEnabled": true, // for the requesting user
    "isCurrentUser": false
  }]
}
```

The app mirrors these types in `DataLayer/Rooms/RoomsDTO.swift` of the Remem repository.

## iOS app setup for push

1. In Xcode select the **Application** target, open **Signing & Capabilities** and make sure **Push Notifications** is listed. The entitlement is already in `Application/Resources/Remem.entitlements`; with automatic signing, Xcode enables the capability for the `io.remem` App ID.
2. The app asks for notification permission after the first room is created or joined, then sends its device token with `PATCH /v1/users/me`.
3. To test, use two users in one room, for example a device and a simulator. Simulators on Apple silicon Macs receive real pushes. Swipe the room event on one, and the other shows a notification, also while the app is open.
