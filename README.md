# trading_balance_f

Flutter app for tracking OKX and Binance balances, PnL, orders and strategies, with a Python backend (API + strategy worker) for the trade features. Targets: iOS, Android, macOS and web.

## Requirements

- Flutter 3.47+ (Dart 3.11+)
- Xcode (iOS/macOS) with a signing team selected for `Runner`
- Android SDK (Android builds)
- Docker (backend API and worker)
- Node.js 20+ and Python 3 (only to rebuild the 3D avatar assets)
- Vercel CLI (only to deploy the web app)

Install dependencies once after cloning or after changing `pubspec.yaml`:

```bash
flutter pub get
```

## Build-time settings (`--dart-define`)

| Define | Used for | Production value |
|---|---|---|
| `TRADE_API_BASE_URL` | Backend trade/strategy API | `https://api.tradingbalancef.com` |
| `BINANCE_PROXY_URL` | Binance Spot/Margin signed reads on **web** (browsers block direct calls, see `docs/deployment/binance-read-proxy.md`) | `https://api.tradingbalancef.com/binance-proxy` |

Both are optional. Without `BINANCE_PROXY_URL` the web build cannot read Binance Spot/Margin private data (native apps call Binance directly). `TRADE_API_BASE_URL` feeds the backend API clients, but the backend features are currently switched off in the app (`backendFeaturesEnabledProvider` in `lib/core/backend_features.dart` is `false`), so the app runs fine without it.

## Run (development)

List devices:

```bash
flutter devices
```

Web (Chrome):

```bash
flutter run -d chrome --dart-define=BINANCE_PROXY_URL=https://api.tradingbalancef.com/binance-proxy
```

macOS:

```bash
flutter run -d macos
```

iOS simulator, iPhone or Android device: start the simulator/emulator or plug in the phone, take its id from `flutter devices`, then:

```bash
open -a Simulator
```

```bash
flutter emulators --launch <emulator_id>
```

```bash
flutter run -d <device_id>
```

Release mode on a real phone (faster, closer to production):

```bash
flutter run --release -d <device_id>
```

## Build

### Web

```bash
flutter build web --release --dart-define=BINANCE_PROXY_URL=https://api.tradingbalancef.com/binance-proxy
```

Output: `build/web`. Preview it locally:

```bash
python3 -m http.server 8080 --directory build/web
```

Then open http://localhost:8080.

Deploy the web build to Vercel production:

```bash
cd build/web && vercel --prod
```

### Android

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. Install on a connected device:

```bash
flutter install -d <device_id>
```

### iOS

```bash
flutter build ios --release
```

Simulator-only build (no signing):

```bash
flutter build ios --simulator --debug
```

### macOS

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/`. Needs a signing team in `macos/Runner.xcworkspace` (Runner → Signing & Capabilities).

### All release artifacts + web deploy

```bash
./release_build.sh
```

Resolves dependencies once, builds the web, macOS and Android APK release artifacts in parallel, then deploys `build/web` to Vercel production only when all builds succeed. The first deployment may ask you to log in to Vercel and link the project.

## Backend (API + strategy worker)

Managed with Docker through one script:

```bash
./docker_manage.sh build
```

```bash
./docker_manage.sh start
```

```bash
./docker_manage.sh status
```

```bash
./docker_manage.sh logs api
```

```bash
./docker_manage.sh logs worker
```

```bash
./docker_manage.sh rebuild
```

```bash
./docker_manage.sh stop
```

Full syntax: `./docker_manage.sh [--api-only] <build|start|stop|restart|rebuild|status|logs|help> [api|worker]`. By default it manages the API and the worker; `--api-only` leaves the worker alone. Run `./docker_manage.sh help` for details.

Server-side setup for the Binance web proxy: `docs/deployment/binance-read-proxy.md`. Trade API deployment: `docs/deployment/position-trade-api.md`.

## Tests and checks

```bash
flutter analyze
```

```bash
flutter test
```

Avatar page runtime tests:

```bash
node --test tools/avatar/test/
```

## 3D avatar assets

The optional home-screen avatar (Settings → "Nhân vật 3D") is a local web page in `assets/avatar/`. Its bundle and model are generated and committed; rebuild only when changing `tools/avatar/src/` or the model. Details and pinned versions: `tools/avatar/README.md`.

```bash
python3 -I -B tools/avatar/build.py
```

```bash
python3 -I -B tools/avatar/optimize_vrm.py optimize <source.vrm> assets/avatar/avatar.vrm
```

## Agent rules

This repository uses the OptCodex personal rule bundle with the ClaudeCodex Bridge. Start from `AGENTS.md` and `CLAUDE.md`; the binding baseline is `BASELINE_AGENTS_OptCodex-Personal-v1.2.3.md`, and its usage notes are in `README_BASELINE_OptCodex-Personal-v1.2.3.md`.
