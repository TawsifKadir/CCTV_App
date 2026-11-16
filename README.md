# Enrolly

**Employee Enrollment & Identity Management.**

Enrolly is a Flutter app for registering employees with a photograph and browsing employee records. It is the client for the Spring Boot enrollment backend: the app collects the employee's details and photo, and the backend stores the employee, builds the face template and adds them to the recognition watch list. The same codebase runs on **Android**, **iOS** and **desktop/mobile web browsers**.

- The backend is the source of truth. Registrations are saved on the device first and synchronized, so nothing is lost while offline.
- The app does not detect or recognise faces. It only captures or uploads the photograph.
- Operator sign-in is still a **local demo** because the backend has no authentication API yet (see [Authentication](#authentication)).

---

## Quick start

1. Start the Spring Boot backend on port 8080.
2. Run the app:

```bash
flutter pub get
flutter run -d chrome --dart-define=APP_ENV=local
```

3. Sign in with the demo operator, or create an operator account:

| Email | Password |
|---|---|
| `admin@enrolly.demo` | `Admin@123` |

## Backend environments

Every request gets its base URL from the active environment. No URL is hard-coded in services, screens or widgets.

### Where URLs live

All backend URLs are in **`lib/core/config/environment_registry.dart`**:

```dart
static const definitions = <EnvironmentDefinition>[
  EnvironmentDefinition(id: 'local', name: 'Local', localPort: 8080, allowDebugFeatures: true),
  EnvironmentDefinition(id: 'development', name: 'Development', baseUrl: 'http://27.147.174.107:8085'),
  EnvironmentDefinition(id: 'qa', name: 'QA', baseUrl: null),                     // UNCONFIGURED
  EnvironmentDefinition(id: 'production', name: 'Production', baseUrl: null, isProduction: true), // UNCONFIGURED
];
```

- **To configure an environment**, set its `baseUrl` to the server origin, without `/api`. For example: `baseUrl: 'https://qa-api.example.com'`.
- **To add an environment**, append an `EnvironmentDefinition` with a new `id`.
  - For a matching Android build, also add a product flavor with the same name in `android/app/build.gradle.kts`.
  - For iOS, add the flavor to `tool/ios_flavors.rb` and re-run it (see [Build flavors](#build-flavors)).
- **To point one build at another server** without editing the file, use `--dart-define=API_BASE_URL=https://host:port`.

The `/api` prefix is per environment (`apiPrefix`, default `/api`). Endpoint paths are in `lib/core/config/api_endpoints.dart`.

### Running each environment

| Environment | Command |
|---|---|
| Local | `flutter run --dart-define=APP_ENV=local` |
| Development | `flutter run --dart-define=APP_ENV=development` |
| QA | `flutter run --dart-define=APP_ENV=qa` |
| Production | `flutter run --dart-define=APP_ENV=production` |

Builds work the same way: `flutter build apk --dart-define=APP_ENV=local` or `flutter build web --dart-define=APP_ENV=local`. You can also use the provided files, for example `--dart-define-from-file=config/qa.json`.

If no `APP_ENV` is given, the flavor decides. Without a flavor either, the app uses `local`.

**Unconfigured environments fail clearly.** Until QA and Production have URLs, building or running them shows a *Backend not configured* screen that explains what to set. The app never falls back to localhost or to another server.

### Localhost on each platform

The `local` environment picks the host for the platform it runs on:

| Where the app runs | URL used |
|---|---|
| Web browser, iOS simulator, desktop | `http://localhost:8080` |
| Android emulator | `http://10.0.2.2:8080` (the emulator's alias for your computer) |
| Physical phone or tablet | `--dart-define=LOCAL_API_HOST=<your computer's LAN IP>`, for example `192.168.1.20` |

### Switching environments at runtime

Settings → **Environment configuration** (also in the desktop sidebar) shows:

- the build environment and how it was chosen
- the active backend URL
- connection status and the time of the last successful call
- a **Test connection** button

**Build-time vs runtime environments:**

- **Non-production builds** can switch between *configured* environments. The choice is remembered. Choosing Production asks for confirmation. Unconfigured environments are shown greyed out.
- **Production builds are locked** to Production and cannot switch.
- Add `--dart-define=ALLOW_ENV_SWITCHING=false` to lock any build to its own environment.

**What a switch does:**

- creates a new HTTP client, which also cancels requests still running against the old server
- gives each environment its own employee cache (cache keys include the environment id)
- clears the decoded-image cache
- resets search, filter and pagination
- refetches the dashboard and employee list
- resolves photo URLs against the new server

**Seeing which backend you are on:**

- Local and Development builds show a coloured strip with the backend URL across the top.
- The sidebar and dashboard always show an environment badge.
- The registration form shows which server the employee will be saved to.

### Build flavors

| Flavor | Android app id | iOS bundle id | Cleartext HTTP (Android) |
|---|---|---|---|
| `local` | `com.example.cctv_app.local` | `com.kit.cctvApp.local` | allowed (backend on your machine) |
| `development` | `….dev` | `….dev` | allowed (server is plain HTTP) |
| `qa` | `….qa` | `….qa` | HTTPS only |
| `production` | `com.example.cctv_app` | `com.kit.cctvApp` | HTTPS only |

```bash
flutter run --flavor qa --dart-define=APP_ENV=qa
flutter build apk --release --flavor production --dart-define=APP_ENV=production
flutter build ipa --flavor production --dart-define=APP_ENV=production
```

- Each flavor gets its own app id and launcher name (e.g. "Enrolly QA"), so several flavors can be installed side by side.
- `pubspec.yaml` sets `default-flavor: local`, so a plain `flutter run` or `flutter build apk` still works.
- **Android**: flavors are defined in `android/app/build.gradle.kts`. Cleartext HTTP is allowed only in the `local` flavor, through a manifest placeholder. It is never enabled globally. If a dev or QA server really is plain HTTP, change that flavor's `usesCleartextTraffic`.
- **iOS**: schemes and `Debug-/Release-/Profile-<flavor>` build configurations are generated by `ruby tool/ios_flavors.rb`. Run `cd ios && pod install` afterwards. The script is idempotent: add a flavor to its `FLAVORS` map and re-run it. App Transport Security already exempts `localhost` and IP addresses, so the local backend works without weakening ATS.
- **Web** ignores flavors. Use `--dart-define=APP_ENV=…`.

## Client builds vs admin builds

| | Production (client mode) | Local / Development / QA (admin mode) |
|---|---|---|
| Navigation | Dashboard, Employees, Register, Synchronization, Settings | the same, plus Environment Configuration and Diagnostics |
| Environment badge / backend URLs | hidden | shown |
| Diagnostics (network inspector, sync log, local database, test data) | not compiled in | available |
| Settings | profile, appearance, camera, sync, connection, data, privacy, about | the same, plus backend, build info and connection-check interval |

- **Compile-time switch:** the mode comes from `kProductionBuild` (`lib/core/config/app_features.dart`), which is a compile-time constant derived from `APP_ENV` or the build flavor.
- **Admin code is removed from production, not hidden:**
  - Admin routes are never registered with the router.
  - The request recorder is never installed in the HTTP client.
  - The compiler strips admin-only code from production builds. In the web build output, the production bundle contains no diagnostics code and the development bundle does.
- **Preview client mode on a dev build:** add `--dart-define=CLIENT_MODE=true`. Admin mode can never be turned on in a production build.

## Offline-first operation

Registrations are never lost because the network is down.

### Connectivity

The app tracks two signals:
- **Device network**, from `connectivity_plus`.
- **Backend reachability**, checked by calling `GET /api/employee/list?size=1`. The backend has no health endpoint.

Checks run every 60 s while online, back off exponentially (5 s, 10 s, 20 s … up to 2 min) while the server is unreachable, and stop while there is no network. Every real API call also updates the status.

The status bar shows one of:
- **Online** — the server is reachable.
- **Offline** — the device has no network.
- **Server unavailable** — the network is up but the server can't be reached.
- **Checking…**

### Registration

1. The record and its photo are always saved on the device first.
2. If the server is reachable, the app uploads at once and stores the server's id with the record. The record is then **SYNCED**.
3. If the device is offline, the server is down, or the network fails during upload, the employee stays on the device and the user sees *"Employee saved on this device. Synchronization will resume when the server becomes available."* The record is **PENDING_SYNC**, or **LOCAL_ONLY** when automatic sync is off.
4. If the server *rejects* the data (a 4xx response, for example no face detected), the backend's message is shown on the form and nothing is kept.

### Storage

Storage uses Hive: app-private files on Android and iOS, IndexedDB on the web. Records and photos survive app restarts, device restarts and browser refreshes. Each record stores:

- `localId` (a UUID) and `serverId`
- `employeeNo`, name, date of birth, designation
- the photo reference and the server's photo URL
- `enrollmentSource`
- created and updated times
- `syncStatus`, last attempt, last success, last error
- `backendEnvironmentId`

### Sync states

| State | Meaning |
|---|---|
| `LOCAL_ONLY` | On this device only; never uploaded (automatic sync was off) |
| `PENDING_SYNC` | Waiting to be uploaded |
| `SYNCING` | Upload in progress |
| `SYNCED` | On the server |
| `FAILED` | The last attempt failed; the record is safe on the device. Shown as **Needs review** when the outcome was uncertain |

### Synchronization

- **Automatic:** sync starts when the server becomes reachable, if automatic sync is on. There is an optional *Wi-Fi only* setting. Transient failures back off from 30 s up to 30 min.
- **Manual:** the user can run **Sync now** (on the dashboard, employee list, Sync screen and status bar), **Retry failed**, or sync a single employee from its profile.
- **Sync now while offline** never starts an upload. Instead it explains that the records are safe and offers *Retry connection / Try again / Cancel*.
- Only one batch runs at a time. A batch stops when the server becomes unreachable, instead of failing every remaining record.

### Duplicate safety

The backend has **no idempotency key**, so the app guards against duplicates itself:

1. A record is marked `SYNCING` and saved *before* the request is sent.
2. Only one upload per record can run at a time.
3. The server's response is saved immediately.
4. If the outcome is uncertain, the record is not retried blindly. Uncertain outcomes are a timeout after sending, a dropped connection, a 5xx response, a response blocked by the browser, or the app being closed mid-upload. The record becomes **Needs review**.
5. Before any retry of a record that needs review, the app searches the server (`GET /api/employee/list?query=<name>`) for an employee with the same name, date of birth and designation that no other local record is linked to.
   - If it finds one, it links the local record to that employee instead of uploading again.
   - If it finds none, it uploads normally.

This greatly reduces duplicates but **cannot guarantee** none. See the backend recommendations below.

### Employee list

- Device records that are not yet on the server are pinned above the server results. Server records keep server-side paging.
- Records registered from this device are matched to the server by server id, so nothing appears twice.
- Filters: All / On server / Local only / Pending sync / Failed sync, with counts.
- Offline, server records come from a copy saved on the device. Search and source filters still work, and the copy is labelled with **"Last updated …"** so it is never shown as live.

### Dashboard

- **Device figures** — saved locally, awaiting sync, synced from this device — are always live.
- **Server figures** are live when online. Offline they show the last known value with its update time, or "—" when unknown (never 0).

### Not supported, because the backend has no endpoint

- Editing or deleting employees.
- Uploading local modifications. There is no edit UI, so records can't be changed locally.

## Recommended backend enhancements

1. **Client-generated external ID / idempotency key** on `POST /api/employee/add` (for example an `Idempotency-Key` header, or an `externalId` field stored with the employee). This would make duplicate prevention exact; `localId` is ready to be sent as that key.
2. **A lightweight health endpoint** (e.g. `GET /actuator/health`) for reachability checks.
3. **`GET /api/employee/{id}`**, plus update and delete endpoints, if editing and deleting are needed.
4. **CORS** for the web app's origin, and `spring.servlet.multipart.max-file-size=10MB`.
   - Without CORS, a browser can send a registration but not read the response. The app then treats the outcome as uncertain and reconciles before retrying.

## Backend integration

### Register an employee: `POST /api/employee/add`

The request is sent as `multipart/form-data` with exactly the backend's `EmployeeForm` fields:

| Field | Value |
|---|---|
| `name` | trimmed text |
| `dateOfBirth` | `YYYY-MM-DD` |
| `designation` | trimmed text |
| `photo` | file part `photo.jpg` / `photo.png` with `image/jpeg` / `image/png` |

**Photos:**

- The photo is validated before upload: JPEG or PNG only (checked by file signature), and at most 10 MB.
- On Android and iOS it is also re-encoded as JPEG in a background isolate, with EXIF rotation fixed and the longest edge capped at 1600 px.
- On the web, a valid original file is sent unchanged.

**Responses:**

- Any `2xx` response (normally `201`) is a **successful registration**.
- If the response has `liveWatchList: false` or a `warning`, the success screen shows that warning ("recognition not active yet"). It does not show a failure.
- The response is parsed tolerantly: only `liveWatchList` and `warning` are relied on, and the employee fields are shown when present.
- When registration fails, the backend's own message is shown, for example `{"error":"Enter a valid date of birth."}`.

### List employees: `GET /api/employee/list?page=&size=&query=&source=`

- **Paging** is done by the server. The default page size is 24 and the app never asks for more than 100. Mobile shows compact Previous/Next controls. Desktop shows numbered pages, "Page X of Y" and the total count.
- **Search** waits 400 ms after typing stops and resets to page 0.
- **Source filter chips**: All (no `source` parameter), Photo Upload (`source=photo`), Camera Capture (`source=capture`).
- **Photos**: `photoUrl` (for example `/api/employee/1/photo`) is resolved against the active environment. Images are decoded at display size and cached. When a photo is missing or fails to load, a coloured initials avatar is shown instead.

### Dashboard figures

All dashboard figures come from the list endpoint's `totalElements`:

- total employees
- photo uploads (`source=photo`)
- camera captures (`source=capture`)

If a request fails, the figure shows **"—" / Unavailable**, never `0`. "Employee records" shows the first page in the order the server returns it. "Recent activity" is a log of what happened **on this device** (registrations, sign-ins, environment changes).

### Error handling

Errors are mapped in `lib/core/network/api_exceptions.dart`:

- HTTP 400, 401, 403, 404, 409, 413, 422 and 5xx
- connection refused, DNS failure and timeout
- invalid JSON and empty responses

Users only see friendly messages, never stack traces. In debug builds of Local and Development, requests are logged as method, URL, status and time only. Bodies, photos and query values are never logged.

## Architecture

```
lib/
  main.dart                 resolve build environment → open storage → run app
  app.dart                  MaterialApp.router, light/dark themes, ThemeMode.system, reduced motion
  core/
    config/                 app_environment (build env, dart-defines), environment_config,
                            environment_registry (← backend URLs), api_endpoints
    network/                api_client (Dio), api_interceptors, api_exceptions
    routing/                GoRouter + auth redirect, responsive AppShell (bottom bar / sidebar)
    theme/  widgets/  utils/
    services/providers.dart settings, activity log, demo auth
  data/                     local storage (Hive), settings/activity/operator models, demo auth API
  features/
    environments/           active environment, API client, connection status, Environment screen
    employees/              models, EmployeeApiService, EmployeeRepository, list + profile screens
    registration/           EmployeeRegistration/EmployeePhoto (validation), controller, form, success
    face_capture/           camera capture view and photo preparation
    dashboard/  activity/  settings/  authentication/
tool/
  generate_branding.dart    crops the branding photo into icon sources
  ios_flavors.rb            creates iOS flavor schemes/configurations
```

- **State management**: Riverpod.
  - The active environment drives the API client.
  - The API client drives the employee repository.
  - The repository drives the list query and pages.
  - When the environment changes, Riverpod rebuilds this chain.
- **Navigation**: GoRouter.
  - Phones: bottom bar with Dashboard, Employees, a raised **Register** button, Activity and Settings.
  - Tablets and desktops: a collapsible sidebar with Dashboard, Employee Management, Register Employee, Settings, Environment Configuration and Logout.
- **Employee profile**: the backend has no get-by-id, update or delete endpoint. The profile is opened from the list and is read-only.

## Authentication

The two backend APIs do not authenticate, so operator sign-in is a **clearly labelled on-device demo** (`DemoAuthApi`). Passwords are stored as salted PBKDF2 hashes.

When a real auth API exists:

1. Implement `AuthApi` (`lib/data/remote/api_contracts.dart`) over `ApiClient`.
2. Return it from `authApiProvider`.
3. Return the token from `authHeaderProvider` (`lib/core/services/providers.dart`). The HTTP client and photo requests already send it as an `Authorization` header.

## Themes

- The app follows the device's light/dark setting by default (`ThemeMode.system`) and updates live when the setting changes.
- Settings → Appearance offers **System / Light / Dark**.
- The dark theme is its own warm charcoal palette with the same peach accent, not an inversion of the light theme.
- Colours come from `AppPalette` (a `ThemeExtension`) and the `ColorScheme`. Widgets do not hard-code light colours.

## Performance work

Each fix below addresses a cause found in the old code:

| Problem | Fix |
|---|---|
| The Register button's pulse ran **forever**, rebuilding widgets every frame, so the app never stopped rendering | Pulses 3 times, painter-driven with no rebuilds, inside a `RepaintBoundary` |
| `InkSparkle` splash compiled a shader on first tap (a hitch on Android) and repainted every frame | `InkRipple` |
| Camera overlay ran a `Path.combine` boolean operation every frame over the live preview | Static even-odd dim layer, plus an animated outline painter isolated with `RepaintBoundary` |
| A 3-second tip timer called `setState` on the whole camera view, including `CameraPreview` | Tip pill owns its timer; the preview sits in its own `RepaintBoundary`; the shutter flash uses a `ValueNotifier` |
| Every list/table row created its own `flutter_animate` controller | Only the first 8 items animate, using one lightweight controller each; `flutter_animate` removed |
| The auth screen had a floating card that rebuilt every frame, forever | Transform-only `SlideTransition` in a `RepaintBoundary` |
| The success checkmark rebuilt a widget tree each frame | Paint-only animation |
| An indeterminate progress bar stayed mounted at opacity 0 and kept animating | Mounted only while loading |
| Lists were built eagerly with `Wrap` | `CustomScrollView` with `SliverGrid`/`SliverList` builders |
| Images were decoded at full size | `cacheWidth` set to the display size on avatars, previews and the logo |
| Page transitions were 320 ms and stacked with content entrance animations | 220 ms fade (with a small slide for detail pages) |

Reduced-motion settings (the OS setting or Settings → Reduce motion) turn off decorative animations.

These changes were checked by reading the code and by tests. They have not been profiled on a device yet. To measure frame times on a mid-range Android phone, use `flutter run --profile` with DevTools.

## Branding and app icon

- The supplied photograph is kept unchanged in `assets/branding/source_photo.jpg`.
- `dart run tool/generate_branding.dart` crops it into these files:
  - `app_icon.png` (iOS, web, macOS, legacy Android)
  - `adaptive_background.png` (an Android adaptive icon, with a wider crop so the face stays inside the mask)
  - `app_logo.png` (256 px, the in-app logo)
- `dart run flutter_launcher_icons` then generates all the launcher icon sizes. The web favicon is a 64 px version of the logo.
- To rebrand, change the name in `lib/core/constants/app_constants.dart` and the photo in `assets/branding/`, then re-run both commands.

## Testing

```bash
flutter analyze
flutter test
```

| Area | Tests cover |
|---|---|
| API | multipart field names and content type, ISO date format, photo part, 10 MB and format validation, 201 parsing, watch-list warning treated as success, list parsing with nulls, query parameters (page, size cap, search, source), error mapping for each status and network failure, photo URL resolution (including context paths), repository cache and TTL |
| Environments | localhost per platform, LAN host override, APP_ENV versus flavor, unconfigured and unknown environments fail, invalid and non-HTTPS production URLs, production lock, runtime switching (base URL, query reset, per-environment cache, photo URLs), persistence, connection status |
| Themes | system light and dark, live updates, manual overrides, returning to System, dark palette |
| UI | every page at 4 screen sizes with no overflow, navigation items, dashboard figures including "unavailable", list loading, error, retry, debounced search, filters and pagination, profile fields, registration validation, success and warning screens |

The tests run against the real Dio client with a fake HTTP adapter (`test/helpers/test_env.dart`). No server is needed.

**Live smoke test** (opt-in, safe for live servers; it never creates an employee):

```bash
flutter test test/live --dart-define=LIVE_API_BASE_URL=http://27.147.174.107:8085
```

## Backend requirements and known limitations

- **CORS (web)**: the browser blocks API calls and photo downloads unless the backend allows the web app's origin, for example `http://localhost:<port>` during `flutter run -d chrome`. Add CORS for `/api/**` on the Spring side. If photos are blocked, the app falls back to an `<img>` element.
- **Upload size**: Spring Boot's default multipart limit is 1 MB. Set `spring.servlet.multipart.max-file-size=10MB` and `max-request-size` to at least 10 MB so that web uploads, which are not downscaled, work up to the 10 MB the form allows.
- **Enrollment source**: the backend decides `enrollmentSource`. A photo taken with the app's camera is still uploaded through `/employee/add`, so it is recorded as the backend chooses, probably `photo`.
- **Not available yet**: there are no backend endpoints for get-by-id, update, delete, authentication or statistics, so the app offers none of these features. Deep links to an employee profile only work from the list.
- **Order**: the list's sort order is defined by the backend.
- **Device testing**: camera capture has been verified to build on Android, iOS and web, but not tested on physical devices in this round.
