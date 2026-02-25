# TidalDrift v1.4 — LocalCast Gets Real

99 commits. 15 version bumps. 4 logo redesigns. Two complete re-implementations of the UDP heartbeat system. A memory corruption arc that spanned five straight patch releases. A brief identity crisis where the app was called "Neural Bridge"... what was I thinking? And somewhere around v1.3.43, I decided VNC was too slow and built an entire screen streaming engine from scratch using nothing but Apple frameworks.

This is that release.

---

## LocalCast — the headline

LocalCast replaces VNC for LAN streaming. ScreenCaptureKit for capture, VideoToolbox for H.264/HEVC encoding, Metal for rendering, raw UDP for transport. The whole pipeline runs in-process — no ffmpeg, no GStreamer, no external daemons. Sub-frame latency on a gigabit LAN.

The thing I'm most excited about is app streaming. You can stream a single app from another Mac and use it like it's running natively on yours — its own window, full input, resizable. Open Xcode on your Mac Studio from your laptop on the couch. Run a build on a remote machine and watch it in real time. Pair on code without screen sharing your entire desktop. It's the feature that made me realize this wasn't just a VNC replacement. 

### New in v1.4

- **End-to-end encryption** — All streaming traffic encrypted with AES-256-GCM. Authentication uses your saved device credentials (same password as VNC/file sharing), so there's nothing extra to configure. Key exchange via HKDF-SHA256 with per-session nonces — the password never touches the wire.

- **Retina-quality streaming** — Fixed a bug where window and app captures used point dimensions instead of pixel dimensions on Retina displays. Quality presets (Ultra/High/Balanced/Low) cap resolution from 4K down to 720p depending on what your LAN can handle.

- **Remote window resize** — Resize the viewer window, and the streamed app's window resizes to match. Uses the Accessibility API to programmatically set the target window size. Skipped on loopback (would fight with yourself).

- **Aspect ratio preservation** — Full-screen no longer stretches the video. Letterboxes or pillarboxes as needed. Fixed a timing race in the Metal renderer where resize events were reading stale drawable sizes.

- **Input rate limiting** — Configurable token bucket (default 120 events/sec) on the host side. Prevents a misbehaving client from flooding CGEvent injection. Adjustable in settings from 60/sec to unlimited.

- **Collapsible viewer toolbar** — The Apps button and stats overlay are tucked behind a small pill at the top of the viewer. Click to expand, click to collapse. Video fills the full window by default.

- **Stability fixes** — Use-after-free prevention in VideoEncoder/VideoDecoder deinit, force-unwrap crash fix in UDPTransport, fragment reassembly safety limits, GPU memory management via periodic texture cache flushes, draw-on-demand rendering.

### Introduced in v1.3.43

- **LocalCast engine** — Full display, single window, and single app capture modes. H.264 and HEVC encoding with configurable bitrate (15–100 Mbps) and frame rate (up to 60fps). Custom UDP transport with packet fragmentation and reassembly. Metal rendering with inline compiled shaders.

- **Remote input forwarding** — Mouse and keyboard events captured in the viewer, normalized to 0–1 coordinates, sent over UDP, injected on the host via CGEvent. Supports clicks, drags, scroll, and key events. Automatically disabled on loopback connections.

- **Remote app picker** — Browse running apps on the host machine from the viewer. Switch between full display and app-specific streaming on the fly. Host enumerates apps via ScreenCaptureKit's SCShareableContent.

- **Bonjour discovery** — Host advertises via `_tidaldrift-cast._udp`. Client discovers automatically. No IP addresses to type.

---

## Everything else that got me here

### Network discovery & peer system

What started as basic Bonjour scanning evolved through multiple rewrites. I rebuilt the peer discovery system three times — first with NetService, then Network.framework, then a dns-sd command-line workaround when the framework approach hit Bonjour service conflicts. Devices are now remembered between launches, stale entries auto-cleanup on scan, and your own machine is highlighted and filtered from the menu bar.

### TidalDrop file transfer

Drag-and-drop file transfers between Macs over UDP. Started simple, broke repeatedly, got fixed repeatedly. Smart send detects mounted shares and uses them when available. Configurable destination folder. I re-implemented the transfer protocol twice from a stable baseline after the first version caused app hangs.

### Clipboard sync

Cross-machine clipboard sharing. Started as an experimental feature behind a toggle, graduated to enabled-by-default after proving stable. Syncs text, images, and file references between paired TidalDrift instances.

### SSH integration

Remote Login (SSH) configuration built into the onboarding flow. One-click SSH enablement with automatic user authorization. Quick SSH button on device cards opens Terminal with the connection pre-filled. Port 22 active scanning for discovery.

### Permissions & diagnostics

macOS permissions are a nightmare and I built the tooling to match. Self-healing PermissionHealthService detects stuck permissions. Permission Diagnostic tool explains exactly what's wrong and how to fix it. Screen Recording permission handling that avoids the System Settings popup loop. Installation cleanup detects and removes duplicate app bundles.

### Build & release pipeline

Developer ID signed builds, automated DMG creation, install-to-Applications workflow. The build script auto-kills old instances before launching. Release builds for distribution. I rewrote the build system itself (xcodebuild replaced the SPM-based approach) after hitting code signing and resource bundling issues.

### UI & branding

The app icon went through at least four iterations (wave + swirl, "SPICY" wave, simple wave, ultra-thin wave symbol) before landing on the current design. Device cards lost their hover expansion. Experimental features moved from popup sheets to tabs. The toolbar was simplified. There was a "Neural Bridge" branding phase that lasted exactly two commits.

### Stability arc (v1.3.2 – v1.3.9)

Seven patch releases focused entirely on not crashing. Memory corruption from thread-unsafe dictionary access. NWConnection premature deallocation. dns-sd process handler crashes. Thread-safe deviceCache. Thread-safe resolve dictionaries. Every one of these was a "how did this ever work" moment.

---

## What's next

All of this was developed and tested using loopback mode — a debug feature that adds a 127.0.0.1 device so you can prove the entire pipeline on a single machine. Capture, encode, UDP transport, decode, Metal render, input capture, serialize, send, deserialize — the full round trip, just talking to yourself. Input injection is skipped on loopback (otherwise CGEvent.post moves your real cursor and you get a feedback loop that's equal parts hilarious and unusable). It's a surprisingly effective way to develop a networked streaming engine without a second computer.

Cross-machine testing is next — I need to validate the full LAN path on a second Mac. If that checks out, this ships. After that:

- Audio capture and forwarding
- Adaptive bitrate based on packet loss
- Clipboard sync during LocalCast sessions
- File drop into the viewer window
- Latency measurement from heartbeat RTT
