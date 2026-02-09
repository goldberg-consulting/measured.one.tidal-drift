# TidalDrift v1.4 — LocalCast Gets Real

LocalCast started as a proof-of-concept: can we build a low-latency screen streaming engine using nothing but Apple frameworks? Turns out, yes. This release takes it from "works on my machine" to something you'd actually want to use.

## What's new

- **End-to-end encryption** — All streaming traffic is now encrypted with AES-256-GCM. Authentication uses your saved device credentials (same password you use for VNC/file sharing), so there's nothing extra to set up. Key exchange uses HKDF-SHA256 with per-session nonces — the password never touches the wire.

- **Retina-quality streaming** — Fixed a bug where window and app captures were using point dimensions instead of pixel dimensions on Retina displays. Streaming a 2x window now captures at full resolution. Quality presets (Ultra/High/Balanced/Low) cap the resolution from 4K down to 720p depending on what your LAN can handle.

- **Remote window resize** — When you resize the viewer window, the streamed app's window resizes to match. Uses the Accessibility API to programmatically set the target window size. Skipped on loopback (would fight with yourself).

- **Aspect ratio preservation** — Full-screen no longer stretches the video. Letterboxes or pillarboxes with black bars as needed. Fixed a timing race in the Metal renderer where resize events were using stale drawable sizes.

- **Input rate limiting** — Configurable token bucket (default 120 events/sec) on the host side. Prevents a misbehaving client from flooding CGEvent injection. Adjustable in settings from 60/sec to unlimited.

- **Collapsible viewer toolbar** — The Apps button and stats overlay are now tucked behind a small pill at the top of the viewer. Click to expand, click to collapse. Video fills the full window by default.

- **Stability fixes** — Use-after-free prevention in VideoEncoder/VideoDecoder deinit, force-unwrap crash fix in UDPTransport, fragment reassembly safety limits, GPU memory management via periodic texture cache flushes.

## What's next

Pending cross-machine testing (loopback is proven, need to validate the full LAN path on a second Mac). If that checks out, this ships. After that:

- Audio capture and forwarding
- Adaptive bitrate based on packet loss
- Clipboard sync during LocalCast sessions
- File drop into the viewer window
- Latency measurement from heartbeat RTT
