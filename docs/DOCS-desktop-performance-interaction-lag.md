# Linux desktop performance, part 2: interaction lag

The second half of the investigation started in
[desktop-performance-findings.md](desktop-performance-findings.md), which
covers frame rate. Split only to keep each file under the 250-line cap;
the author signposted the two parts explicitly.

## Part 2: the interaction lag is a separate, larger problem

The 60 Hz cap above is real but is **not** what the user is complaining about.
Driven by the user directly (synthetic input having proved unreliable), with an
instrument that logs individual outliers plus event-loop blocking rather than
per-second percentiles:

- Stalls are **raster-dominated**. Build (Dart) stays at 0.1-0.9 ms throughout;
  single frames reach 76 ms of raster at a 1280x1417 window.
- The UI isolate does block occasionally (65-101 ms at startup and on some
  interactions), but this is the minority of the problem.
- The user reports the lag is **constant, on every interaction** — which rules
  out both GitHub sync (periodic) and shader compilation (one-off, warms up).
- Impeller/Vulkan halved slow frames (18 → 7) and removed the worst 76 ms
  spike, but the user perceived **no difference**.

**Raster cost scales hard with window pixel count**, and the user runs the app
fullscreen on the 4K monitor. Measured under a nested X server:

| Window | Achieved | build p50/p90 | raster p50/p90 |
|---|---|---|---|
| 1280x720 | 68.5 fps | 0.30 / 0.40 ms | 1.50 / 2.00 ms |
| 3840x2160 | 19.9 fps | 0.40 / 0.50 ms | 8.40 / 44.60 ms |

Those first 4K figures came from plain (software) Xephyr and overstated raster.
Repeated **fullscreen on the real 3840x2160 monitor**:

| Window (real display) | Achieved | build p50 | raster p50 |
|---|---|---|---|
| 1280x720 | 68.6 fps | 0.30 ms | 1.50 ms |
| 3840x2160 | **18.6 fps** | 0.30 ms | **2.70 ms** |

This is the key result, and it is *not* a rasterisation wall. At 4K each frame
costs ~3 ms of a 16.7 ms budget, yet the app achieves 18.6 fps (~54 ms per
frame). Roughly **50 ms per frame is dead time** — neither build nor raster.
The bottleneck is the presentation/swap path, which is also why Impeller never
helped: Impeller changes rasterisation, not presentation.

### It is Flutter, not todo

Run through an identical harness, the **stock `flutter create` counter app** —
one spinner on a blank Scaffold, zero todo code — collapses the same way:

| App | 1280x720 | 3840x2160 |
|---|---|---|
| stock Flutter counter | 68.5 fps | **20.5 fps** |
| todo | 68.5 fps | **20.6 fps** |

Flutter's Linux embedder manages ~20 fps rendering a **blank screen** at 4K.
Build time is 0.1-0.4 ms throughout. No application-level change can fix this.

Size curve (harness), showing the cliff begins at 1440p:

| size | Mpx | fps | frame cost | dead time |
|---|---|---|---|---|
| 1280x720 | 0.92 | 68.5 | 1.70 ms | 12.9 ms |
| 1920x1080 | 2.07 | 60.5 | 2.40 ms | 14.1 ms |
| 2560x1440 | 3.69 | 40.3 | 3.70 ms | 21.1 ms |
| 3840x2160 | 8.29 | 20.6 | 8.80 ms | 39.8 ms |

Related upstream reports:
[#66463](https://github.com/flutter/flutter/issues/66463) (Linux desktop failure
based on window size on 4K monitors),
[#88996](https://github.com/flutter/flutter/issues/88996) (high frame latency on
Linux desktop).

## Test harness (for iterating without taking over the user's screens)

`Xephyr -glamor` runs a nested X server that renders through OpenGL on the real
GPU. Validated against ground truth: it reproduced the 4K symptom at 19.8 fps
versus the real display's 18.6 fps. It inflates raster attribution (7.2 ms vs
2.7 ms real), so use it for pass/fail, **not** for attributing where time goes.

Plain `Xephyr` without `-glamor` is a software X server and is useless here: it
copies a ~33 MB framebuffer per frame at 4K and dominates the measurement.

**The harness is validated for the Flutter desktop embedder only.** A Chrome
run inside it reported 10 fps at 4K; measuring the same page on the real display
gave 142.9 fps, confirming that number was a harness artifact (Chrome disables
GPU acceleration on an unrecognised nested display). Never benchmark a browser
inside it.

## The decisive comparison: same content, same machine, real 4K display

The identical spinner probe, rendered at 3840x2160 on the real monitor:

| Renderer | Achieved at 4K |
|---|---|
| Flutter **Linux desktop embedder** | **20.5 fps** |
| Flutter **Web (CanvasKit) in Chrome** | **142.9 fps** (cadence p50 7.00 ms) |

A **7x difference**, with the same framework and the same Dart code. This is not
a hardware limit, a driver limit, or an application limit — it is specific to
Flutter's Linux desktop embedder. It validates the web route at the size that
actually matters.

## Why the 60 Hz cap exists

`libflutter_linux_gtk.so` imports `gdk_monitor_get_refresh_rate` (and GTK
correctly reports 144.00 Hz here — verified independently), but imports **no**
`gdk_frame_clock_*` symbols; the engine falls back to a fixed 60 FPS vsync
waiter.

This is a known, open upstream limitation:
[flutter/flutter#183703 — "[Proposal] Support high refresh rate (>60) on
Linux"](https://github.com/flutter/flutter/issues/183703). Opened 2026-03-14,
labelled **P2**, **no assignee, no linked PR, no milestone**. Linux is the last
Flutter platform without >60 Hz support. Related:
[#93058](https://github.com/flutter/flutter/issues/93058) (Windows, since
fixed), [#49757](https://github.com/flutter/flutter/issues/49757).

## Implication for the "switch technology" question

A rewrite in another language is **not** warranted by the evidence. The same
Flutter framework and the same Dart code reach ~143 fps on this exact machine
when built for web and run in Chrome. Only the Linux *desktop embedder* is
capped.

The leading candidate is therefore **shipping the desktop app as a Flutter web
build in a Chrome `--app` window**, reusing the UI and domain code.

**Validated at 4K on the real display: 142.9 fps vs the desktop embedder's
20.5 fps on identical content.** That settles the renderer question.

What remains unproven is todo's *own* widget tree on web: the probe is a
spinner, and web CanvasKit raster plus WASM/JS build costs differ from the
desktop's 0.30/1.50 ms. Given desktop build time is only 0.3 ms and the web
renderer has 7x the headroom, this is very likely fine — but the proof-of-
concept should build the actual app and re-measure before the port is finished.

What is reused is the UI and domain logic. The platform-adapter layer needs web
variants throughout: persistence durability under a browser profile, token
storage, device auth, sync-on-background (Page Visibility API), and the
launch mechanism (local server vs `file://`).

Port surface (the storage seam is small, because `crdt_sync_dart` was designed
for it):

- `LogStore` is deliberately `dart:io`-free and documented as web-usable;
  `FileLogPersistence` is already isolated behind the `crdt_sync_io.dart`
  entrypoint. `LogPersistence` is a two-method interface (`read()` /
  `write(String)`), so a web implementation over IndexedDB/localStorage is
  roughly 15 lines.
- `github_client.dart` has **no** `dart:io` and uses `package:http`; the GitHub
  REST API sends permissive CORS headers, so sync works from a browser origin.
- `sqlite_crdt`/`sqflite_common_ffi` remain only for the one-time legacy DB
  migration (`note_repository.dart:350`), which does not apply on web and can be
  skipped behind `kIsWeb`.
- `path_provider` is only used to choose the file path for `FileLogPersistence`;
  unnecessary on web.
- `shared_preferences`, `url_launcher`, `share_plus`, `file_selector`,
  `flutter_secure_storage` all have web implementations.

### Known costs of the web route (both are security regressions)

1. **The token loses the OS keystore.** Commit `9841aec` deliberately moved the
   GitHub token off plaintext and into the OS keyring via
   `flutter_secure_storage`. A Chrome `--app` build cannot reach the keyring;
   `flutter_secure_storage` on web falls back to WebCrypto-wrapped
   `localStorage`. That is materially weaker than what is shipping today and
   partially undoes that commit.
2. **Device-flow auth breaks.** GitHub's OAuth device-flow endpoints
   (`github.com/login/device/code`) do not send CORS headers, so one-tap device
   auth will not work from a browser origin. The settings screen's
   paste-a-personal-access-token path would have to become the desktop auth
   route — which also means a long-lived PAT living in the weaker storage above.

These two stack, and they are the strongest argument against the web route.

## Agreed plan (decided 2026-07-20)

The desktop app moves to a Flutter **web** build launched in Chrome. Decisions
taken, so the next session can start from here:

- **Auth:** simple PAT pasted into `localStorage` (via
  `flutter_secure_storage_web`). The local-helper design that would have kept
  the OS keyring and device-flow auth was considered and **rejected** for
  simplicity. Consequences accepted: the token is no longer in the keyring, and
  the AES-GCM wrapping is obfuscation only (the wrap key sits in the same
  `localStorage`).
  - Requires a **classic PAT with "No expiration"** to be a one-time paste.
  - The launcher must pin a **fixed port** and a **fixed `--user-data-dir`**,
    and call `navigator.storage.persist()`. Any of those changing loses the
    token: `localStorage` is keyed by origin and lives in the Chrome profile.
- **The Linux desktop build is deleted**, not kept as a fallback. (Android is
  unaffected and remains a normal Flutter mobile build.)
- **Launch:** a wrapper script serves the web build on a fixed port and opens
  Chrome with `--app=http://localhost:<port>`.
- **Done-condition:** the real todo app, fullscreen at 4K, sustains **>=100 fps**
  while scrolling the notes list, and sync works against `kuhyx/syncs`.

Still to be specified before coding: the `WebLogPersistence` implementation,
what replaces `path_provider`/`sqflite` on web (the legacy sqlite migration path
at `note_repository.dart:350` does not apply), packaging/`install_arch.sh`
changes, and how the desktop entry launches the wrapper.

## Alternatives, if the web route is rejected

Ranked by cost. All require re-implementing the UI, and the two non-Dart options
also require a third `crdt_sync` implementation (it exists today only in Python
and Dart).

1. **Accept 60 fps.** Zero cost. The app is genuinely smooth *at* 60.
2. **Qt 6 / QML (C++).** Vulkan RHI, real 144 Hz, best NVIDIA/X11 record. Weeks.
3. **Rust + Slint.** Lightweight, but the highest total cost.

Not recommended: **Tauri** — on Linux it renders via WebKitGTK, which has its
own NVIDIA/X11 DMABUF rendering bugs; it trades one renderer problem for
another.
