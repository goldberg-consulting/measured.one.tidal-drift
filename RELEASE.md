# Release History

## v1.4.3: Open-Source Release

**Date:** April 2026
**Tag:** `v1.4.3`
**Commits:** 127

This is the first public release of TidalDrift as an open-source project under the MIT License.

The release represents 127 commits across roughly 18 months of development, encompassing a menu-bar-first redesign, a custom screen streaming engine (LocalCast), two complete security audits, and the infrastructure required for open-source collaboration: CI, linting, branch protection, and updated documentation.

### What works

| Feature | Status | Notes |
|---|---|---|
| Menu-bar command center | Stable | Primary UI; all device actions accessible from the popover |
| Bonjour/mDNS network discovery | Stable | Discovers `_rfb._tcp`, `_smb._tcp`, `_ssh._tcp`, and TidalDrift peers |
| One-click VNC, SMB, SSH connections | Stable | Opens macOS-native handlers; credentials stored in Keychain |
| TidalDrop file transfer | Stable | Peer-to-peer via mounted SMB or direct TCP fallback |
| Clipboard sync | Stable | Text, images, and file references between paired instances |
| Wake-on-LAN | Stable | MAC auto-discovery from ARP cache |
| Guided setup wizard | Stable | Configures Screen Sharing, File Sharing, SSH, Firewall |
| Full-desktop VNC streaming (Tier 1) | Stable | Uses macOS built-in Screen Sharing; no custom code |
| In-app integration test suite | Stable | 22 tests covering Bonjour, networking, crypto, file transfer, streaming |

### What does not yet work

| Feature | Status | Notes |
|---|---|---|
| LocalCast app-window streaming (Tier 2) | Not fully implemented | Architecture complete, code compiles and runs, but cross-machine reliability, window eligibility detection, and failure diagnostics have known gaps. See `TidalDrift/LocalCast/README.md`. |
| Audio capture and forwarding | Not implemented | `LocalCastConfiguration.captureAudio` exists but is disabled |
| Adaptive bitrate | Not implemented | No packet loss feedback loop yet |

### Open-source infrastructure (new in v1.4.3)

- **SwiftLint** configuration (`TidalDrift/.swiftlint.yml`): 0 errors on the existing codebase, 173 warnings. Thresholds are set to pass current code while catching regressions. Noisy rules (trailing whitespace, trailing newline) are disabled pending a cleanup pass.
- **GitHub Actions CI** (`.github/workflows/ci.yml`): SwiftLint + `swift build` on every PR and push to `main`. macOS 15 runners.
- **Branch protection** on `main`: PRs required, status checks required, force pushes blocked.
- **Documentation** updated: README, CONTRIBUTING, and LocalCast README rewritten to remove emdash usage, flag LocalCast status, and align with writing conventions.

---

## v1.4.1: Hardening

**PRs:** #2, #4, #6, #8, #10, #12, #14

Fourteen pull requests after the v1.4.0 release, the codebase went through a full audit. The scope covered security vulnerabilities, memory leaks, performance regressions in hot paths, concurrency bugs, and resource cleanup. The app is signed, notarized, and stapled for Gatekeeper-clean distribution.

### Security (PR #12)

Five vulnerabilities identified and fixed:

1. **Plaintext password in UserDefaults.** The LocalCast host password was stored via `@AppStorage`, which writes to `~/Library/Preferences` in plaintext. Migrated to Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Legacy values are auto-migrated and deleted. This is the kind of thing that works fine during development and becomes a CVE in production.

2. **Path traversal in TidalDrop.** A malicious peer could send a filename like `../../.ssh/authorized_keys` and write outside the destination folder. Added `sanitizeFilename()` using `URL.lastPathComponent` and rejecting hidden files.

3. **Metadata size bomb.** Incoming TidalDrop metadata had no size limit. A peer could send a multi-GB length prefix and exhaust memory. Added a 1 MB cap.

4. **Shell injection in Bonjour resolution.** Service names from mDNS were interpolated into `dns-sd -L` shell commands without escaping. Sanitized `'` and `\` metacharacters.

5. **Removed `executeWithSudo`.** A deprecated method that passed passwords as command-line arguments, visible to any process via `ps`.

### Memory management (PRs #8, #12, #14)

Four categories of leaks, each discovered the hard way:

- **Window lifecycle.** `LocalCastViewerWindow` and device detail windows created new instances on every open without closing old ones. Added window tracking and reuse.
- **Event monitors.** Global `NSEvent` monitors (keyboard shortcuts, mouse tracking) were added but never removed. Stored references; remove in `deinit`/close.
- **Timer leaks.** Multiple `Timer.scheduledTimer` calls without invalidation on teardown. Added cleanup in `disconnect()` and `deinit`.
- **Strong captures in closures.** Singleton dispatch closures capturing `self` strongly, preventing deallocation even when the object graph should have released.

Additional resource cleanup in PR #14: `NWPathMonitor` and UDP listener cancelled in `stopBrowsing()`, incoming NWConnections tracked and cancelled on teardown, 60-second peer prune timer to prevent unbounded dictionary growth, `CVMetalTextureCache` flushed on viewer close, diagnostic timer capped at 60 seconds.

### Performance (PRs #12, #14)

- **Per-frame allocations in the video pipeline.** `VideoEncoder.convertAVCCToAnnexB` copied the entire buffer to `[UInt8]`, then built output byte-by-byte. Replaced with `withUnsafeBytes` and `Data(capacity:)` pre-allocation. Same treatment applied to `VideoDecoder`, `PacketProtocol.serialize/deserialize`, and `UDPTransport.FragmentHeader.deserialize`.
- **`Date()` in hot paths.** Every packet timestamp created a `Date` object (heap allocation). Replaced with `CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970`.
- **`RelativeDateTimeFormatter` per render cycle.** Allocated once per offline device per SwiftUI render. Now a static shared instance.
- **Fragment eviction.** Changed from O(n) `keys.min()` to O(1) via tracked `oldestBufferedFrameId`.
- **Discovery debouncing.** `updatePublishedDevices()` debounced by 200ms to coalesce rapid discovery events into a single sort + serialize + UserDefaults write.

### Concurrency (PRs #10, #12, #14)

- `UDPTransport` counters (`sendCount`, `receiveCount`, `frameCounter`) mutated from multiple queues without synchronization. Protected with `NSLock`.
- `UDPTransport.sessionKey` protected with a dedicated lock (written during auth, read on every packet).
- `StreamingNetworkService`: NWConnection captured weakly in state handlers to break retain cycles; per-connection `DispatchQueue` replaced with shared service queue.
- `SharingConfigurationService`: all five `Process.waitUntilExit()` calls replaced with `terminationHandler` to avoid blocking the Swift concurrency cooperative thread pool.
- `AtomicFlag` replaced with `os_unfair_lock` for actual thread safety. The previous implementation was a plain `Bool` with no synchronization, which could cause `withCheckedContinuation` to resume twice.

### Architecture change: VNC-first streaming (PR #6)

Replaced the custom streaming engine with macOS built-in Screen Sharing (VNC) as the primary streaming path. The original LocalCast engine (ScreenCaptureKit + VideoToolbox + Metal + UDP) is preserved as Tier 2 for app-window streaming.

The reasoning: VNC is battle-tested, supports full Retina, handles clipboard and drag-and-drop natively, and does not require Screen Recording permission prompts that reset on every code signature change (i.e., every development build). The custom pipeline exists because VNC cannot stream a single app window in its own native-feeling window. That capability is the differentiator, but it is not yet reliable enough to be the default.

### Other fixes

- **Dock icon visibility** (PR #2): `LSUIElement` was set in Info.plist but the activation policy was not enforced at launch. Fixed. Menu bar device list clipped by fixed-height frame; wrapped in ScrollView.
- **Peer highlighting** (PR #4): TidalDrift peers appear at the top of the device list with an accent border. Persistent custom display names via `tdname` Bonjour TXT record field.
- **Network tests** (PR #10): `NWListener` requires Local Network TCC permission, which resets on every code signature change. Replaced with raw BSD sockets bound to `INADDR_LOOPBACK`.
- **Logging** (PR #14): world-readable `/tmp/tidaldrift_share.log` replaced with `os.Logger`.

---

## v1.4.0: LocalCast

The headline release. 99 commits from the initial commit to this point.

LocalCast is a custom screen streaming engine built entirely with Apple frameworks: ScreenCaptureKit for capture, VideoToolbox for H.264/HEVC encoding, Metal for rendering, raw UDP for transport. The pipeline runs in-process with no external dependencies (no ffmpeg, no GStreamer, no external daemons).

### Design choices and rationale

**UDP over TCP.** TCP's congestion control and retransmission add latency worse than dropping a frame. Lost fragments result in a dropped frame; the next keyframe (approximately every 1 second) resyncs. Input events are also UDP, which is acceptable for mouse moves on a LAN. This is a latency-first design choice; a reliability-first design would choose TCP and accept the latency cost.

**Annex B over AVCC.** VideoToolbox outputs AVCC (length-prefixed NAL units). The pipeline converts to Annex B (start-code delimited) on the wire, making the stream self-describing: the decoder finds NAL boundaries without out-of-band signaling, and SPS/PPS are inline with keyframes. The tradeoff is slightly larger wire format, but the simplicity of a self-contained stream outweighs the overhead on a LAN.

**Inline Metal shaders.** Compiled from source strings at init time rather than shipped as a `.metallib`. This avoids SPM resource bundling issues and ensures the renderer works in any build configuration. The tradeoff is a one-time compilation cost at viewer launch.

**1200-byte fragment size.** Chosen to stay under typical MTU (1500) with room for IP/UDP headers. Keyframes can exceed 300 KB, splitting into approximately 250 fragments. Reassembly is frame-ID based with a 100-frame LRU. This is conservative; a more aggressive choice would probe path MTU, but the additional complexity is not justified on a LAN.

**End-to-end AES-256-GCM encryption.** All streaming traffic encrypted. Authentication uses saved device credentials (same password as VNC/file sharing). Key exchange via HKDF-SHA256 with per-session nonces; the password never touches the wire.

### New capabilities in v1.4.0

- Full display, single window, and single app capture modes
- H.264 and HEVC encoding at configurable bitrate (15--100 Mbps) and frame rate (up to 60fps)
- Retina-quality streaming with quality presets (Ultra/High/Balanced/Low) from 4K to 720p
- Remote mouse and keyboard input with configurable token bucket rate limiting (default 120 events/sec)
- Remote app picker: browse running apps on the host, switch streams on the fly
- Remote window resize via Accessibility API
- Aspect ratio preservation with letterboxing/pillarboxing
- Collapsible viewer toolbar
- Loopback demo mode for development (input injection skipped to avoid cursor feedback)

---

## v1.0 through v1.3: Foundation

The first 80 commits built the core product: network discovery, device management, file transfer, and the menu-bar UI.

### Network discovery

The peer discovery system was rewritten three times: first with `NetService`, then `Network.framework`, then a `dns-sd` command-line workaround when `Network.framework` hit Bonjour service conflicts. The `dns-sd` approach introduced shell command execution, which later required security hardening (see v1.4.1).

Devices are remembered between launches via UserDefaults persistence. Stale entries auto-cleanup on scan. The current machine is highlighted and filtered from the menu bar list.

### TidalDrop

Peer-to-peer file transfer. The transfer protocol was reimplemented twice from a stable baseline after the first version caused app hangs. Smart send detects mounted SMB shares and uses them when available; falls back to direct TCP.

### Stability arc (v1.3.2 through v1.3.9)

Seven patch releases focused on crash elimination. Root causes, in order: thread-unsafe dictionary access, `NWConnection` premature deallocation, `dns-sd` process handler crashes, thread-unsafe `deviceCache`, thread-unsafe resolve dictionaries. Each fix addressed a concurrency bug that, in retrospect, was always there but only manifested under specific timing conditions.

### Branding

The app icon went through at least four iterations before landing on the current design. There was a brief "Neural Bridge" branding phase (v1.3.11, v1.3.12) that lasted exactly two commits. The project was renamed back to TidalDrift in v1.3.13.

---

## Roadmap

The following items are planned but not yet implemented. No timeline commitments.

- Audio capture and forwarding over LocalCast
- Adaptive bitrate based on packet loss feedback
- Clipboard sync during active LocalCast sessions
- File drop into the LocalCast viewer window
- Latency measurement from heartbeat RTT
- Full reliability pass on LocalCast app-window streaming (Tier 2)
