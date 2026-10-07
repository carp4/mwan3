# mwan3 — IPv6 track-source re-derive fix (local patch fork)

> **Not affiliated with the OpenWrt project.** This is a standalone local patch
> fork of the `mwan3` package. It is **not** a fork of the
> `openwrt/packages` repository and is not endorsed by or connected to its
> maintainers.

The current upstream `mwan3track` (2.12.2) has a defect that intermittently
misreports a healthy WAN as offline on carriers that rotate the delegated IPv6
prefix:

- `mwan3track` resolves the tracking source address (`SRC_IP`) exactly once,
  in `firstconnect()`, and never refreshes it.
- When the upstream rotates the delegated `/64`, the pinned address is
  deleted. The LD_PRELOAD sockopt wrapper's `bind()` then fails with
  `EADDRNOTAVAIL`, every track probe dies, and a link that is still carrying
  traffic is marked offline until someone restarts mwan3.

This repo carries the fix: a `refresh_src_ip()` step that re-derives the
tracking source on every round (preferring a non-deprecated global address,
falling back through deprecated-but-routing addresses, and to a route-valid
source when nothing answers), plus `track_ping()`, which probes IPv6 members
with a plain, unmarked `ping -I <source>` instead of the wrapper socket that
cannot bind from a deleted address. IPv4 keeps the existing `WRAP` path.

## Contents

| File | Purpose |
| --- | --- |
| `files/usr/sbin/mwan3track` | patched tracker (2.12.2 + fix) |
| `Makefile` | upstream 2.12.2 with `PKG_RELEASE` bumped 2 → 3 |
| `mwan3-v6-rederive-src.patch` | the fix as a re-appliable patch |
| `reapply-mwan3-patch.sh` | re-applies the patch after a feeds update reverts the tracker |
| `files/`, `src/`, `test.sh`, `test-version.sh` | unmodified upstream package content |

## Provenance

- Upstream source: `https://github.com/openwrt/packages`, `net/mwan3`, at
  upstream commit `24d2074662472662eb3a540b535b0cab8f7d7460`.
- Version: `2.12.2-r2` upstream → `2.12.2-r3` here (`PKG_RELEASE` bumped so a
  rebuilt ipkg is not silently reused).
- License: GPL-2.0, as declared in the upstream `Makefile`
  (`PKG_MAINTAINER Florian Eckert <fe@dev.tdt.de>`).
- Baseline commit `29efbb4` is the pristine upstream tree; commit `3fc0954`
  adds the fix. The whole history is two commits, plus this documentation.

## Using it

Drop this directory into an OpenWrt package feed (e.g. as
`feeds/packages/net/mwan3`) and rebuild mwan3 — nothing else changes. When a
feeds update reverts the tracker to upstream, run:

```sh
./reapply-mwan3-patch.sh        # applies the fix to this checkout
./reapply-mwan3-patch.sh --check
```

The script refuses to run (`exit 3`) if the patch no longer applies cleanly —
that is the signal that upstream changed the tracker and the fix needs
re-derivation, not blind re-application.

## Verification

- The `refresh_src_ip()` / `track_ping()` added code is byte-identical to the
  tracker logic that shipped in a production 24.10 mwan3 build and is
  **hardware-validated** on a live unit whose carrier rotates the delegated
  `/64`: with the fix, the WAN stays up through rotations; stock `mwan3track`
  (same version) marks the link offline and only a restart recovers it.
- The port to the current 2.12.2 tracker surface is covered by offline
  checks against the real functions (source re-derivation, route-valid
  fallback, IPv4 no-op, `-I`-bound IPv6 probing, IPv4 `WRAP` passthrough);
  it has not run on 25.12-generation hardware because none exists yet.
- `mwan3-v6-rederive-src.patch` re-applies cleanly to the pristine 2.12.2
  tracker and reproduces the committed tracker byte-for-byte.