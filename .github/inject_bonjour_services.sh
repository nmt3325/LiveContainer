#!/bin/sh
# Inject Bonjour service types into LiveContainer's host Info.plists.
#
# Why this exists
# ---------------
# iOS gates Bonjour browsing/advertising on NSBonjourServices of the
# *installed host app*. Apple peer-to-peer Wi-Fi (AWDL) is only brought up by
# Network.framework for a Bonjour service that is both p2p-enabled
# (includePeerToPeer) and declared there. A guest app running inside
# LiveContainer cannot contribute its own NSBonjourServices, so every service
# type it uses must be present in:
#
#   LiveContainer/Info.plist   - normal launch (guest runs in the host process)
#   LiveProcess/Info.plist     - multitasking launch (guest runs in the appex)
#
# If a type is missing, NWListener/NWBrowser fail with a policy error and
# awdl0 never comes up, so the guest silently falls back to infrastructure
# Wi-Fi or fails outright.
#
# Usage
# -----
#   sh .github/inject_bonjour_services.sh
#   EXTRA_BONJOUR_SERVICES="_myapp._tcp,_myapp._udp" sh .github/inject_bonjour_services.sh
#
# Run from the repo root before `xcodebuild archive`. Idempotent.
set -eu

# Service types this fork always adds.
#   _opensidecar._tcp : OpenDisplay / OpenSidecar (peetzweg/opendisplay and
#                       forks). The name is historical - PROTOCOL.md keeps it
#                       for wire compatibility.
#   *._udp            : cheap insurance for UDP side-channels of the same apps.
DEFAULT_BONJOUR_SERVICES="_opensidecar._tcp _opensidecar._udp _opendisplay._tcp _opendisplay._udp"

EXTRA_BONJOUR_SERVICES="${EXTRA_BONJOUR_SERVICES:-}"

PLISTS="LiveContainer/Info.plist LiveProcess/Info.plist"
PLISTBUDDY=/usr/libexec/PlistBuddy

WANTED=$(printf '%s %s' "$DEFAULT_BONJOUR_SERVICES" "$EXTRA_BONJOUR_SERVICES" | tr ',;' '  ')

print_services() {
	"$PLISTBUDDY" -c "Print :NSBonjourServices" "$1" \
		| sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

for plist in $PLISTS; do
	if [ ! -f "$plist" ]; then
		echo "error: $plist not found (run from the repository root)" >&2
		exit 1
	fi

	for svc in $WANTED; do
		[ -n "$svc" ] || continue
		if print_services "$plist" | grep -Fxq "$svc"; then
			echo "skip  $plist  $svc"
			continue
		fi
		"$PLISTBUDDY" -c "Add :NSBonjourServices: string $svc" "$plist"
		echo "add   $plist  $svc"
	done
done

# Verify, so a broken injector fails the build instead of shipping an IPA that
# silently cannot use AWDL.
status=0
for plist in $PLISTS; do
	if ! plutil -lint "$plist" >/dev/null; then
		echo "error: $plist is not a valid plist after injection" >&2
		status=1
	fi
	for svc in $WANTED; do
		[ -n "$svc" ] || continue
		if ! print_services "$plist" | grep -Fxq "$svc"; then
			echo "error: $plist is missing $svc after injection" >&2
			status=1
		fi
	done
done
[ "$status" -eq 0 ] || exit "$status"

echo
echo "Final NSBonjourServices:"
for plist in $PLISTS; do
	echo "--- $plist"
	"$PLISTBUDDY" -c "Print :NSBonjourServices" "$plist"
done
