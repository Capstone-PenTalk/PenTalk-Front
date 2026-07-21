# pentalk_front

PenTalk Flutter client.

## Server configuration

The app can use one shared backend URL for both REST API and Socket.IO.

Example:

```bash
flutter run \
  --dart-define=PENTALK_SERVER_URL=https://api.pentalkedu.com
```

If you need to separate API and socket endpoints, these are also supported:

```bash
flutter run \
  --dart-define=PENTALK_API_URL=https://api.pentalkedu.com \
  --dart-define=PENTALK_SOCKET_URL_TEACHER=https://api.pentalkedu.com \
  --dart-define=PENTALK_SOCKET_URL_STUDENT=https://api.pentalkedu.com
```

## Login mode

By default, the login screen calls `POST /auth/login` on the configured server
and stores the returned token. Signup uses `POST /auth/signup`; Google/Kakao
OAuth starts at `/auth/google` and `/auth/kakao`.

For local UI-only testing without server auth:

```bash
flutter run --dart-define=PENTALK_USE_SERVER_LOGIN=false
```
