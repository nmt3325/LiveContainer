# AWDL / Apple peer-to-peer Wi-Fi support in LiveContainer

This fork makes guest apps able to use **Apple peer-to-peer Wi-Fi (AWDL)** -
the radio Sidecar and AirDrop use - so they work with no router, no access
point and no shared Wi-Fi network.

## The problem

iOS decides whether an app may browse or advertise a Bonjour service from the
`NSBonjourServices` array of the **installed host app**. Network.framework only
brings up `awdl0` for a Bonjour service that is

1. created with `includePeerToPeer = true`, and
2. of a service type listed in that array.

A guest app inside LiveContainer has its own `Info.plist`, but it is not the
installed app - LiveContainer is. The guest's `NSBonjourServices` is therefore
ignored, and any service type LiveContainer does not declare is denied. The
visible symptom is `NWListener` failing immediately (`listener failed: …`,
often followed by a restart loop) and `awdl0` never coming up.

Entitlements cannot fix this either: guest entitlements are not applied to the
host, and `com.apple.developer.networking.multicast` needs Apple approval, so
it is not usable for sideloaded builds. The only working lever is the host
`Info.plist`.

## The fix

`.github/inject_bonjour_services.sh` adds the required service types to both
host property lists before the build:

| Plist | Used when |
| --- | --- |
| `LiveContainer/Info.plist` | normal launch - guest runs in the host process |
| `LiveProcess/Info.plist` | multitasking launch - guest runs in `LiveProcess.appex` |

Defaults added on every build:

- `_opensidecar._tcp`, `_opensidecar._udp`
- `_opendisplay._tcp`, `_opendisplay._udp`

`_opensidecar._tcp` is the service type used by
[peetzweg/opendisplay](https://github.com/peetzweg/opendisplay) and its
AWDL-enabled forks; the name is historical and `PROTOCOL.md` keeps it for wire
compatibility. The script verifies its own work with `PlistBuddy` and
`plutil -lint` and fails the build if a type is missing, so a silently
AWDL-incapable IPA cannot be published.

## Building

### GitHub Actions

Run the **AWDL - Build IPA** workflow. It also runs automatically on pushes to
`feat/awdl-**`. Artifacts:

- `LiveContainer-awdl.ipa`
- `LiveContainer-SideStore-awdl.ipa`

To allow extra service types for another guest app, dispatch the workflow with
the `extra_bonjour_services` input, for example `_myapp._tcp,_myapp._udp`.

### Locally

Run the injector once before building, because the committed plists are left
untouched to keep rebases against upstream clean:

```sh
sh .github/inject_bonjour_services.sh
# optionally: EXTRA_BONJOUR_SERVICES="_myapp._tcp" sh .github/inject_bonjour_services.sh
```

## Adding your own app

Find the service type your app passes to `NWListener.Service` /
`NWBrowser` (or `MCNearbyServiceAdvertiser`), then either dispatch the
workflow with `extra_bonjour_services`, or add it to
`DEFAULT_BONJOUR_SERVICES` in the script. Wildcards are not supported by iOS -
every type must be listed literally, including the `._tcp` / `._udp` suffix.

## Caveats

- Local network permission is granted to LiveContainer as a whole, not per
  guest app, matching LiveContainer's existing permission model.
- Changing `Info.plist` changes the bundle, so the app must be re-signed and
  reinstalled - an existing LiveContainer install will not pick this up.
- AWDL and infrastructure Wi-Fi share one radio and time-slice it, so
  throughput drops when both are active, and more so with multiple peers.
