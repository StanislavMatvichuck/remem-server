# Remem Rooms server

Swift [Vapor](https://vapor.codes) server behind the Rooms feature of Remem. Rooms let users share one event: every member gets the room event in their events list, each swipe is sent here, and other members receive a push notification unless they turned notifications off for that member.

## Run locally

```bash
swift run RoomsServer serve
```

Without `DATABASE_URL` the server uses a local SQLite file `rooms.sqlite`. Without APNs keys, notifications are only logged. The iOS app reads the server address from `RememRoomsServerURL` in `Application/Resources/Info.plist`; the default `http://localhost:8080` works with the simulator.

```bash
swift test
```

## Deploy on Railway

1. Create a project with a **Postgres** service.
2. Add a service from this GitHub repository and set its **Root Directory** to `/Server`. Railway builds `Dockerfile` using `railway.json`, which also sets the `/health` healthcheck.
3. Set the variables below on the server service, then generate a public domain under **Settings → Networking**.
4. Put the domain into `RememRoomsServerURL` in `Application/Resources/Info.plist`, for example `https://<your-service>.up.railway.app`.

Migrations run automatically at startup.

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | yes | `${{Postgres.DATABASE_URL}}` reference to the Postgres service |
| `PORT` | provided | Injected by Railway |
| `RAILWAY_PUBLIC_DOMAIN` | provided | Injected by Railway, used to build room links |
| `PUBLIC_URL` | no | Overrides the base of room links, e.g. a custom domain |
| `APNS_KEY_ID` | for push | Key ID of an APNs auth key (`.p8`) from Apple Developer → Keys |
| `APNS_TEAM_ID` | for push | Apple Developer team ID |
| `APNS_PRIVATE_KEY` | for push | Contents of the `.p8` file; `\n` sequences are accepted instead of line breaks |
| `APNS_TOPIC` | no | App bundle ID, default `io.remem` |
| `APNS_ENVIRONMENT` | no | `production` for TestFlight and App Store builds, otherwise sandbox |
| `APP_URL_SCHEME` | no | Scheme that join links open, default `remem` |
| `AUTO_MIGRATE` | no | `false` disables migrations at startup |

## API

All bodies are JSON, and dates are ISO 8601. Every `/v1` endpoint except registration requires `Authorization: Bearer <token>`.

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| `GET` | `/health` | | `ok` |
| `POST` | `/v1/users` | `{name, color}` | `201 {user, token}`, token is shown once and stored hashed |
| `PATCH` | `/v1/users/me` | `{name?, color?, deviceToken?}` | `User` |
| `GET` | `/v1/rooms` | | `[Room]` of the current user |
| `POST` | `/v1/rooms` | `{name, eventName}` | `201 Room`, creator becomes the first member |
| `GET` | `/v1/rooms/:roomId` | | `Room`, members only |
| `POST` | `/v1/rooms/:roomId/members` | | `Room`, joins the room, repeated calls are ignored |
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

The client mirrors these types in `DataLayer/Rooms/RoomsDTO.swift`.

## iOS app setup for push

- `Application/Resources/Remem.entitlements` contains `aps-environment`, so the App ID needs the Push Notifications capability. With automatic signing, Xcode adds it.
- The app asks for notification permission after the first room is created or joined, then sends the device token with `PATCH /v1/users/me`.
