# pentalk_front

PenTalk Flutter client.

## Server configuration

The app can use one shared backend URL for both REST API and Socket.IO.

Example:

```bash
flutter run \
  --dart-define=PENTALK_SERVER_URL=http://54.180.142.244:3000
```

If you need to separate API and socket endpoints, these are also supported:

```bash
flutter run \
  --dart-define=PENTALK_API_URL=http://54.180.142.244:3000 \
  --dart-define=PENTALK_SOCKET_URL_TEACHER=http://54.180.142.244:3000 \
  --dart-define=PENTALK_SOCKET_URL_STUDENT=http://54.180.142.244:3000
```

## Login mode

By default, the login screen calls `POST /auth/dev-login` on the configured
server and stores the returned token.

For local UI-only testing without server auth:

```bash
flutter run --dart-define=PENTALK_USE_SERVER_LOGIN=false
```
