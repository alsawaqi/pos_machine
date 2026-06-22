# Sunmi Support Ticket — T3 PRO 10.1" USB customer display: touch not routed to the secondary display

> Ready to send to Sunmi developer/technical support (partner.sunmi.com or your Sunmi contact).
> Everything below is captured from the actual device via `adb` / `dumpsys` / `logcat`.

---

**Subject:** T3 PRO + 10.1" USB customer display (NP521) — panel touch stays associated to the main display (displayId=0); `setScreenTpSwitch` is received but does not re-associate the digitizer to the customer display.

## Summary

On a SUNMI T3 PRO with the **optional 10.1" USB customer display**, our app renders an independent UI on the customer display (Android `Presentation` on the secondary `Display`). The display output is correct, but **touches on the 10.1" customer panel are delivered to the main/operator display (displayId=0), not to the customer display (displayId=2)**. As a result, tapping the customer screen activates whatever is under the same coordinates on the operator screen.

We call `SubScreenManager.setScreenTpSwitch(sn, true)` (equivalently the AIDL `IUsbScreenInterface.setParameter(sn, 7, 1, 0, "")`). The call **is received** by `com.sunmi.usbscreen` (confirmed in logcat), but the customer-panel touch digitizer (`SUNMI NP521`) remains associated with `displayId=0` in `dumpsys input`.

We need the supported way for a customer/third-party app to **receive the 10.1" customer-panel touch on the customer display**, or a firmware-side input-to-display association for this device.

## Device / hardware

| Item | Value |
|---|---|
| Model | SUNMI T3 PRO |
| OS | SUNMI OS, Android 13 (SDK 33) |
| Customer display | 10.1" USB customer display (SKU C02020003), HD 1280×800, capacitive multitouch |
| Customer display id (Android) | `displayId=2`, uniqueId `virtual:com.sunmi.usbscreen,10140,Sunmi-USBDisplay-ZC02P58K40309,0` |
| Sub-display module (from `settings global` → `sub_display_device_info`) | `cpu=T113-S3, model=NP521, screen_size=10.1, sn=ZC02P58K40309, touch_port=0, ver_app=1.3.6, ver_fw=1.3.6` |
| Touch input device | `SUNMI NP521` — `/dev/input/event3`, classes `TOUCH | TOUCH_MT | EXTERNAL`, vendor `0x324f` product `0x0182`, Location `usb-xhci-hcd.2.auto-1.2.1.4.1/input0`, UniqueId `ZC02P58K40309` |
| USB-screen service app | `SunmiUsbScreen_privapp_v2.5.4` (`/system_ext/priv-app/...`), service `com.sunmi.usbscreen/.service.SubScreenService` |

## Expected vs actual

- **Expected:** With touch enabled on the sub-screen, a tap on the 10.1" customer panel is delivered to the window showing on the customer display (displayId=2).
- **Actual:** The tap is delivered to the main/operator display (displayId=0). The `SUNMI NP521` digitizer is associated to displayId=0 and never moves to displayId=2.

## Evidence

**1) The customer display is an independent (non-mirrored) secondary display — output works:**
```
Display 2:  mPrimaryDisplayDevice = Sunmi-USBDisplay-ZC02P58K40309
            mWindowManagerMirroring = false   (1280×800, layerStack 2)
dumpsys input → Viewport VIRTUAL: displayId=2,
   uniqueId=virtual:com.sunmi.usbscreen,10140,Sunmi-USBDisplay-ZC02P58K40309,0,
   logicalFrame=[0,0,1280,800]
```

**2) `setScreenTpSwitch`/`setParameter` IS received by the Sunmi service:**
```
I darren-IUScrBinder: IUsbScreenBinder.setParameter<com.example.pos_machine>:
   sn=ZC02P58K40309, type=7, key=1, value=0, str=
```
(We also send the screen-on control, type=2. Both are received.)

**3) …but the touch digitizer stays on displayId=0:**
```
dumpsys input → device "SUNMI NP521":
  Touch Input Mapper (mode - DIRECT):
    AssociatedDisplay: hasAssociatedDisplay=true, isExternal=true, displayId=''
    Viewport INTERNAL: displayId=0, deviceSize=[1920,1080]
  AssociatedDisplayUniqueId: <none>
```
So the panel's 1280×800 touches are mapped into the main display's 1920×1080 space → they land on the operator screen.

**4) The app cannot self-associate** (normal, non-system app):
```
adb shell pm grant com.example.pos_machine android.permission.ASSOCIATE_INPUT_DEVICE_TO_DISPLAY
→ SecurityException: ... is not a changeable permission type
```

## What we already tried

- Switched from the `com.sunmi.usbscreen.ACTION_SET_CONTROL` broadcast to **binding the service** and calling `IUsbScreenInterface.setParameter(sn, 7, 1, 0, "")` (== `SubScreenManager.setScreenTpSwitch(sn, true)`). The service receives it (logcat above), but the digitizer association does not change.
- Verified the same app code works correctly on an **Android emulator** with a standard virtual secondary display (touch lands on the secondary display) — so the app-side rendering/Presentation is correct; the difference is the physical USB-HID digitizer association on the real device.
- Confirmed the public PeripheralSDK exposes no display-association / touch-routing API beyond the binary `setScreenTpSwitch`.
- In your own **Customer Display Settings → Customer display 2 → Touch Function**, the touch toggle is **already ON**; toggling it off then on does **not** change the `NP521` association (it stays `displayId=0`). So the customer panel's touch remains mapped to the main display even with Sunmi's own Touch Function enabled. There is no user-facing setting (or Android developer option) to map the panel's touch to the customer display.

## Reproduction

1. T3 PRO + 10.1" USB customer display attached.
2. App shows an Android `Presentation` (its own content) on `displayId=2`; call `setScreenTpSwitch(sn, true)`.
3. `dumpsys input` → `SUNMI NP521` shows `Viewport INTERNAL: displayId=0`.
4. Physically tap the 10.1" customer panel → the tap activates the operator screen (displayId=0), not the customer UI.

## Questions / requests to Sunmi

1. **Is there a supported API** for a customer/third-party app to make the 10.1" USB customer-panel touch (`SUNMI NP521`) be delivered to the **customer display (displayId=2)** — beyond `setScreenTpSwitch`? If so, what is the exact call/sequence?
2. If routing is handled in firmware, can you provide a **device input-port association** (e.g. `input-port-associations.xml` / IDC `touch.displayId`) mapping the `NP521` digitizer (port `usb-xhci-hcd.2.auto-1.2.1.4.1/input0`, sn `ZC02P58K40309`) to the `com.sunmi.usbscreen` virtual display, for the **T3 PRO + 10.1" customer display (usbscreen app v2.5.4 / module fw 1.3.6)**?
3. If this requires a **privileged/system app**, what is the path on the T3 PRO (priv-app whitelisting / platform signing / Sunmi signing program) to obtain `ASSOCIATE_INPUT_DEVICE_TO_DISPLAY` or to have Sunmi's service associate the digitizer for our app?
4. Alternatively, please confirm **how Sunmi's own customer-display app receives this panel's touch**, and whether there is a supported surface/SDK for us to render our customer UI through it (rather than a raw `Presentation`).

## Contact / environment

- App package: `com.example.pos_machine` (normal user app, debug-signed)
- Android 13 (SDK 33); `com.sunmi.usbscreen` v2.5.4; sub-display module fw/app 1.3.6
- We can provide full `dumpsys input`, `dumpsys display`, and logcat on request.
