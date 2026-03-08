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

## v1.4.1 — Hardening

Fourteen pull requests after the v1.4 release, the codebase went through a full audit and hardening pass. Everything from memory leaks to security vulnerabilities to hot-path allocations. The app is now signed, notarized, and stapled for Gatekeeper-clean distribution.

### Dock icon + scrolling fix (PR #2)

The app was showing in the Dock despite being a menu-bar-only app. `LSUIElement` was set in Info.plist but the activation policy wasn't being enforced at launch. Fixed, and the device list in the menu bar popover wasn't scrollable — it was clipped by a fixed-height frame. Wrapped in a ScrollView with proper height constraints.

### TidalDrift peer highlighting + custom naming (PR #4)

TidalDrift peers (other Macs running the app) now appear at the top of the device list with a red accent border so they stand out from generic Bonjour services. Added persistent custom display names that survive IP changes — each peer broadcasts a `tdname` field in its Bonjour TXT record. Names are editable from device detail and persist in UserDefaults.

### TidalCast VNC-first architecture (PR #6)

Replaced the custom streaming engine with macOS's built-in Screen Sharing (VNC) as the primary streaming path. The original LocalCast engine (ScreenCaptureKit + VideoToolbox + Metal + UDP) is preserved and documented but no longer the default. The reason: VNC is battle-tested, supports full Retina, handles clipboard and drag-and-drop natively, and doesn't require Screen Recording permission prompts that reset on every rebuild.

The new architecture adds app-window streaming on top of VNC — the client can select a single app from the host and present it in its own native-feeling window, with full input forwarding. This is the key differentiator over plain Screen Sharing.

### Memory management (PR #8)

Four categories of leaks fixed:
- **Window lifecycle**: `LocalCastViewerWindow` and device detail windows were creating new instances on every open without closing old ones. Added window tracking and reuse.
- **Event monitors**: Global NSEvent monitors (keyboard shortcuts, mouse tracking) were added but never removed. Stored references and remove in `deinit`/close.
- **Timer leaks**: Multiple `Timer.scheduledTimer` calls without invalidation on teardown. Added proper cleanup in `disconnect()` and `deinit`.
- **Strong captures in closures**: Singleton dispatch closures capturing `self` strongly, preventing deallocation even when the object graph should have been released.

### Network test fix (PR #10)

The UDP and TCP port-bind integration tests were failing with `POSIXErrorCode(rawValue: 22): Invalid argument` after every rebuild. Root cause: `NWListener` requires Local Network TCC permission, which gets reset when the code signature changes (i.e., every build). Replaced with raw BSD sockets bound to `INADDR_LOOPBACK`, which bypass TCC entirely. Also fixed `AtomicFlag` to use `os_unfair_lock` for actual thread safety — the previous implementation was a plain `Bool` with no synchronization, which could cause `withCheckedContinuation` to resume twice.

### Critical audit — security, performance, concurrency (PR #12)

A comprehensive audit of the entire codebase produced 15 critical and high-priority fixes:

**Security**
- **Plaintext password in UserDefaults**: The LocalCast host password was stored via `@AppStorage` (i.e., plaintext in `~/Library/Preferences`). Migrated to Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Legacy values are auto-migrated and then deleted.
- **Path traversal in TidalDrop**: A malicious peer could send a filename like `../../.ssh/authorized_keys` and write outside the destination folder. Added `sanitizeFilename()` using `URL.lastPathComponent` and rejecting hidden files.
- **Metadata size bomb**: Incoming TidalDrop metadata had no size limit — a peer could send a multi-GB length prefix and exhaust memory. Added a 1 MB cap.
- **Shell injection in Bonjour resolution**: Service names from mDNS were interpolated into `dns-sd -L` shell commands without escaping. Sanitized `'` and `\` metacharacters.
- **Removed `executeWithSudo`**: A deprecated method that passed passwords as command-line arguments (visible in `ps` output).

**Performance**
- **Per-frame allocations in video pipeline**: `VideoEncoder.convertAVCCToAnnexB` was copying the entire buffer to `[UInt8]`, then building output byte-by-byte. Replaced with `withUnsafeBytes` and `Data(capacity:)` pre-allocation. Same treatment for `VideoDecoder`, `PacketProtocol.serialize/deserialize`, and `UDPTransport.FragmentHeader.deserialize`.
- **`Date()` in hot paths**: Every packet timestamp was creating a `Date` object (heap allocation). Replaced with `CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970`.

**Memory management**
- **`HostSession` missing `deinit`**: The transport, encoder (wrapping `VTCompressionSession`), and input injector were never cleaned up. Added `deinit` to stop transport, invalidate encoder, and restore apps.
- **`ScreenCaptureManager` retain cycle**: `SCStream` holds a strong reference to its `SCStreamOutput` delegate. Without explicit `stopCapture` + nil in `deinit`, neither object is ever released.

**Concurrency**
- **`UDPTransport` counter races**: `sendCount`, `receiveCount`, and `frameCounter` were mutated from multiple queues without synchronization. Protected with `NSLock`.

### Remaining audit polish (PR #14)

The second audit pass addressed lower-priority findings:

**Resource cleanup**
- `NetworkDiscoveryService`: `NWPathMonitor` and UDP listener were never cancelled — now cleaned up in `stopBrowsing()`
- `TidalDropService`: incoming NWConnections tracked and cancelled on teardown via new `stopListening()` method
- `TidalDriftPeerService`: 60-second prune timer removes peers unseen for 5+ minutes, preventing unbounded dictionary growth
- `MetalRenderer`: `deinit` flushes `CVMetalTextureCache` to release GPU memory when the viewer closes
- `ClientSession`: diagnostic timer capped at 60 seconds to prevent indefinite firing

**Performance**
- `DiscoveredDevice`: `RelativeDateTimeFormatter` was allocated per offline device per render cycle — now a static shared instance. `Date()` calls across `isOnline`/`isStale`/`isRecentlyConfirmed`/`lastSeenText` consolidated into a single `age` property.
- `UDPTransport`: fragment eviction changed from O(n) `keys.min()` to O(1) via tracked `oldestBufferedFrameId`
- `NetworkDiscoveryService`: `updatePublishedDevices()` debounced by 200ms to coalesce rapid discovery events into a single sort + serialize + UserDefaults write

**Thread safety**
- `UDPTransport.sessionKey` protected with a dedicated `NSLock` (written during auth, read on every packet)
- `StreamingNetworkService`: NWConnection captured weakly in state handlers to break retain cycles; per-connection `DispatchQueue` allocations replaced with the shared service queue

**Logging**
- `StreamingNetworkService`: world-readable `/tmp/tidaldrift_share.log` replaced with `os.Logger`
- `SharingConfigurationService`: all 5 `Process.waitUntilExit()` calls replaced with `terminationHandler` to avoid blocking the Swift concurrency cooperative thread pool

### Signing + notarization

The DMG is now Developer ID signed with hardened runtime, notarized by Apple, and stapled. Gatekeeper will allow installation without the "unidentified developer" warning. The release build script (`build-release.sh`) handles the full pipeline — see `TidalDrift/.env.example` for the required notarization credentials.

---

## What's next

- Audio capture and forwarding
- Adaptive bitrate based on packet loss
- Clipboard sync during LocalCast sessions
- File drop into the viewer window
- Latency measurement from heartbeat RTT
