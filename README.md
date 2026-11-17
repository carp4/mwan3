# mwan3 — IPv6 track-source re-derive fix (local patch fork)

> **Not affiliated with the OpenWrt project.** This is a standalone local patch
> fork of the `mwan3` package. It is **not** a fork of the
> `openwrt/packages` repository and is not endorsed by or connected to its
> maintainers.

The current upstream `mwan3track` (2.12.2) has two defects that misreport a
healthy WAN as offline:

- `mwan3track` resolves the tracking source address (`SRC_IP`) exactly once,
  in `firstconnect()`, and never refreshes it. When the upstream rotates the
  delegated `/64`, the pinned address is deleted. The LD_PRELOAD sockopt
  wrapper's `bind()` then fails with `EADDRNOTAVAIL`, every track probe dies,
  and a link that is still carrying traffic is marked offline until someone
  restarts mwan3.
- Unmarked IPv6 probes are policy-routed onto the failover member. `mwan3_hook`
  sits on `OUTPUT`, and `mwan3_rules` sends every packet with an empty policy
  mark to `mwan3_policy_failover`, which stamps the failover mark. The echo
  request still leaves the member's own device, but the flow is masqueraded
  with the failover uplink's address, so its replies arrive over that uplink.
  The member's own return path is never exercised, and every IPv6 member shares
  the failover uplink's fate.

This repo carries the fix: a `refresh_src_ip()` step that re-derives the
tracking source on every round (preferring a non-deprecated global address,
falling back through deprecated-but-routing addresses, and to a route-valid
source when nothing answers), and a probe path that sends both families through
the wrapper — `FWMARK=MMX_DEFAULT`, `SO_BINDTODEVICE` and the bound source —
with `WRAP_SRC` added for the `refresh_src_ip()` candidate tests.

## Contents

| File | Purpose |
| --- | --- |
| `files/usr/sbin/mwan3track` | patched tracker (2.12.2 + fix) |
| `Makefile` | upstream 2.12.2 with `PKG_RELEASE` bumped 4 → 5 |
| `mwan3-v6-rederive-src.patch` | the fix (both parts) as a re-appliable patch |
| `reapply-mwan3-patch.sh` | re-applies the patch after a feeds update reverts the tracker |
| `files/`, `src/`, `test.sh`, `test-version.sh` | unmodified upstream package content |

## Provenance

- Upstream source: `https://github.com/openwrt/packages`, `net/mwan3`, at
  upstream commit `24d2074662472662eb3a540b535b0cab8f7d7460`.
- Version: `2.12.2-r2` upstream → `2.12.2-r5` here (`PKG_RELEASE` bumped so a
  rebuilt ipkg is not silently reused).
- License: GPL-2.0, as declared in the upstream `Makefile`
  (`PKG_MAINTAINER Florian Eckert <fe@dev.tdt.de>`).
- Baseline commit `29efbb4` is the pristine upstream tree; the fix is carried
  by the commits after it, and `mwan3-v6-rederive-src.patch` is generated from
  that baseline.

## Using it

Pull it in as a feed from this repository:

```sh
# feeds.conf
src-git mwan3 https://github.com/carp4/mwan3.git;main

./scripts/feeds update mwan3
./scripts/feeds uninstall mwan3     # drop the openwrt/packages-feed copy first
./scripts/feeds install mwan3
```

Alternatively, drop this directory into an OpenWrt package feed (e.g. as
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

- Hardware, 25.12 generation: with the fix installed, per-device ICMPv6
  counters (`/proc/net/dev_snmp6/*/Icmp6OutEchos` and `Icmp6InEchoReplies`)
  show the echo request and its reply on the member's own device every cycle,
  and all members stay online with no down events. Control: an unmarked manual
  `ping -6 -I <member source>` still lands its replies on the failover uplink,
  so the policy mark is what changes the path.
- Before the fix the same counters showed the requests leaving the member's
  device while every reply arrived on the failover uplink. An earlier reading
  based on interface packet totals ("the probe leaks to the failover uplink")
  was an artefact of ordinary traffic on those links and is withdrawn.
- The source re-derivation half was validated earlier on a carrier that rotates
  the delegated `/64`: with it the WAN stays up through rotations, while stock
  `mwan3track` (same version) marks the link offline and only a restart
  recovers it.
- The port to the current 2.12.2 tracker surface is covered by offline checks
  against the real functions (source re-derivation, route-valid fallback, IPv4
  no-op, IPv4 `WRAP` passthrough).
- `mwan3-v6-rederive-src.patch` re-applies cleanly to the pristine 2.12.2
  tracker and reproduces the committed tracker byte-for-byte.