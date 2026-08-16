# SharpEmu RAD V31.7.3 — PID/HWND Embedded Host Repair

This revision fixes the V31.7.2 runtime failure where the RAD/BinkPlay window
remained external and SharpEmu never logged either an attach success or an
attach failure.

## Evidence from V31.7.2

The result ZIP reported:

- `RAD_STARTED=1`
- `RAD_HOST_ATTACHED=0`
- `RAD_BRIDGE_ATTACHED=0`
- `RAD_EMBEDDED_HOST_FAILURES=0`
- `STRICT_RAD_EMBEDDED_PROOF=False`

`BINK_RELEVANT.log` stopped immediately after `bink2.rad_required_started`.
That means the old code stalled inside HWND discovery before it reached
`SetParent` or its timeout/error path.

## V31.7.3 change

The old host-window discovery read window captions with
`GetWindowTextLengthW/GetWindowTextW`.  Those functions are removed from the
attach path.

V31.7.3 now:

1. resolves the SharpEmu SDL HWND by current PID, visibility, client area and
   window class;
2. calls `Process.Refresh()` and `MainWindowHandle` for the process started by
   RAD;
3. detects a newly spawned `binkplay.exe` when `radvideo64.exe` delegates the
   renderer;
4. falls back to new top-level HWND enumeration only when the owning process is
   `binkplay` or `radvideo64`; no caption matching is used;
5. hides the renderer HWND, applies `WS_CHILD`, clears popup/caption styles and
   calls `SetParent`;
6. verifies the result with `GetParent`/`IsChild` before showing the child;
7. keeps the child resized to the SharpEmu client area;
8. kills all newly spawned RAD/BinkPlay processes if embedding fails, so a
   desktop player is not silently left behind;
9. follows the actual renderer process for playback completion;
10. keeps the attract-movie external AT9 mix anchored only after verified host
    attachment.

## Expected runtime markers

For every movie:

```
bink2.rad_required_started ...
bink2.rad_host_attach_begin ...
bink2.rad_host_window_ready ...
bink2.rad_renderer_window_ready ...
bink2.rad_host_attached ... verified_parent=True render_location=sharpemu-child-window
bink2.rad_renderer_bound ...
Bink RAD bridge attached: ...
```

If embedding cannot be completed within 6 seconds, the package logs an explicit
`bink2.rad_host_*_failed`/`window_missing` marker and kills the new RAD
processes.  It must not leave an independent BinkPlay window running.

## Same-window vs same-process

This package integrates the official RAD renderer HWND into the SharpEmu
window.  The decoder still executes in the RAD process because the audited RAD
Video Tools installation does not contain the licensed Bink SDK runtime DLL.
The `IRadBinkHostApi` boundary remains in place for a future licensed
same-process backend.

No proprietary RAD/Bink binary, game media, AT9 or WAV file is included.
