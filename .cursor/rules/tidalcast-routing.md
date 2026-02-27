---
description: Routes TidalCast, screen sharing, VNC, and app-window streaming tasks to the correct specialized agent
globs:
  - TidalDrift/LocalCast/**
  - TidalDrift/Services/ScreenShareConnectionService.swift
  - TidalDrift/Services/AppStreamingService.swift
  - TidalDrift/Views/Experimental/AppStreamingView.swift
alwaysApply: false
---

# TidalCast Agent Routing

When working on files matching the globs above, or when the task involves screen sharing, VNC, remote desktop, app streaming, window mirroring, or TidalCast:

## Routing Rules

1. **VNC / macOS Screen Sharing integration** (connecting via `vnc://`, ScreenSharingAgent, _rfb._tcp discovery, authentication):
   → Use the `macos-vnc-specialist` agent

2. **App-window streaming** (capturing a specific window, ScreenCaptureKit filters, presenting remote windows as local NSWindows, input forwarding, the client viewer):
   → Use the `tidalcast-engineer` agent

3. **Both VNC + app streaming** (e.g., "make TidalCast work with VNC for full desktop and custom streaming for app windows"):
   → Use `tidalcast-engineer` as primary (it has VNC fallback context)

4. **Transport layer only** (UDP, PacketProtocol, encoding/decoding without UI context):
   → Use `tidalcast-engineer` agent

## Architecture Decision Record

- **Full desktop sharing** = macOS built-in VNC via `Screen Sharing.app` (no custom code)
- **App/window sharing** = ScreenCaptureKit capture → VideoToolbox encode → UDP transport → Metal render in client NSWindow
- The original fully-custom LocalCast streaming pipeline is **retained as infrastructure** for app-window mode but is **not the primary full-desktop solution** (VNC is)
- All custom streaming code should be documented with comments explaining this architecture split
