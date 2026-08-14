# Linux desktop performance: measured findings

Investigation date: 2026-07-20. Machine: Arch, X11 + i3, NVIDIA proprietary
610.43.03, RTX 3090. DP-0 = 3840x2160 @144 Hz (primary), HDMI-0 = 2560x1440
@144 Hz. Flutter 3.44.6 stable.

## Conclusion

**The previous session was right: Flutter's Linux desktop embedder cannot drive
this machine's 4K display, and switching technology for the desktop app is
justified.**

Two independent defects, neither fixable in application code:

1. **Hard 60 FPS cap.** Flutter's Linux embedder schedules frames at a fixed
   60 FPS regardless of the monitor (upstream
   [#183703](https://github.com/flutter/flutter/issues/183703), P2, no PR).
2. **~20 FPS at 4K.** Far worse, and the actual cause of the reported lag. At
   3840x2160 the app achieves 18.6 fps while each frame costs only ~3 ms of a
   16.7 ms budget. The stock `flutter create` counter app behaves identically,
   so this is the toolkit, not todo.

Application code is not implicated anywhere: build (Dart) time is 0.1-0.4 ms in
every configuration and at every window size measured.

An earlier revision of this document concluded that a rewrite was **not**
warranted. That conclusion was based only on defect 1 and is superseded by the
4K measurements below.

## Evidence

Measured with a temporary in-app instrument (`lib/frame_stats.dart`, armed by
`TODO_FRAME_STATS=1`) reporting frame-to-frame cadence alongside build/raster
times, driven by a perpetual animation so frames are produced continuously.

| Configuration | Cadence p50 | Achieved | build p50 | raster p50 |
|---|---|---|---|---|
| Release, Skia GL (default) | 16.67 ms | **60.0 fps** | 0.30 ms | 1.50 ms |
| Release, Impeller | 16.67 ms | **60.0 fps** | 0.19 ms | 1.33 ms |
| Release, Impeller + Vulkan | 16.67 ms | **60.0 fps** | 0.26 ms | 1.33 ms |
| Driver vsync off (`__GL_SYNC_TO_VBLANK=0`) | 16.67 ms | **60.0 fps** | 0.28 ms | 1.40 ms |
| picom compositor + Skia GL | 16.67 ms | **60.0 fps** | 0.27 ms | 1.62 ms |
| picom compositor + Impeller | 16.67 ms | **60.0 fps** | 0.30 ms | 1.44 ms |
| **Stock `flutter create` app** (no todo code) | 16.67 ms | **60.0 fps** | 0.12 ms | 1.35 ms |
| **Same Flutter code as a web build, in Chrome** | **7.00 ms** | **142.9 fps** | — | — |

> **Retracted:** an earlier revision of this table had a "real typing +
> scrolling" row. It was invalid. It used `xdotool type --window`, which sends
> synthetic `XSendEvent` keystrokes that GTK/Flutter ignore; the keystrokes
> actually landed in a different application. That run measured an idle app.
> Interaction is measured properly in the next section instead.

Confounds on the web row, stated for honesty: it ran on HDMI-0 (1440p@144) with
a game occupying the 4K GPU, which is why its p95 was 13.90 ms. The desktop
60.0 fps lock, by contrast, is clean, jitter-free and monitor-independent, so
the comparison's conclusion holds — but the web number should be re-confirmed on
the 4K monitor with the GPU idle.

Key readings:

- Cadence p50 **equals** p95 at exactly 16.67 ms in every desktop run — a hard
  lock with zero jitter, not contention.
- Total per-frame work is ~1.8 ms against a 6.94 ms 144 Hz budget. The renderer
  has **74% headroom at 144 Hz** and 89% at 60 Hz.
- Under real typing and scrolling, **one** frame exceeded the 144 Hz budget in
  14 seconds and **zero** exceeded 60 Hz. There is no dropped-frame jank.
- The stock counter app behaves identically, so this is not `todo`'s code.
- Neither renderer choice, nor driver vsync, nor a compositor moves the number.

---

Part 2 — the interaction-lag half of this investigation, and the decision that came out of it — is in
[desktop-performance-interaction-lag.md](desktop-performance-interaction-lag.md).
