# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
file below.

- `verify-package-names.sh` — the client catalogue's verification contract: every name in
  [`../lib/clients.nix`](../lib/clients.nix) checked against **upstream Arch** (archlinux.org's
  package search API, the only authority for an `aur = false` claim), the **AUR RPC** (the
  authority for `aur = true`), and its **nixpkgs attribute forced** rather than merely looked up.
  `--surface` additionally realizes each attribute and lists `bin/`, because existence, project
  identity and command surface are three separate questions and at least one candidate in this
  subject is only answered correctly by the third. Reads the names out of the catalogue rather than
  a second hand-kept list.

  That catalogue is **empty today** — which repository owns a package is assigned rather than
  decided there — so the script currently checks nothing. It is here for the same reason the
  backends are: the day a package is assigned, verifying it is running one command, not starting a
  research project. Four likely candidates have already been through it; two turned out to be traps
  and are written up in [`../studies/`](../studies/README.md).

## Why this lives here and not in `checks/`

`checks/` is `nix flake check`-wired and evaluates offline. It can prove how a selection RESOLVES —
and it does, including the invariant that the pacman and AUR lists never intersect, and the
cross-reference between the two catalogues. It cannot prove that a package is in a given repository
today, or that a nixpkgs attribute still forces. Those are facts about the world: they change
without this repository changing, and asserting them at eval time would need either network access
from a pure evaluation or a snapshot that silently goes stale.

So the split is deliberate and matches what every sibling repository does with its own name
verification: eval-time checks for anything internal and deterministic, a hand-run script for
anything that depends on what upstream is shipping this week.

## What is deliberately NOT verified here

**Nothing about the cluster catalogue.** [`../lib/engines.nix`](../lib/engines.nix) names container
image *repositories* and no versions at all — the version of every instance is supplied by whoever
declares it, because a tier runs several majors of one engine at once and this repository has no
concept of a current one. There is no name to check against a registry, and checking that a
repository exists would prove nothing about the tag somebody actually deploys.

What the cluster side does have is a cross-reference into the client catalogue — every engine names
a client, every operator names a control-plane plugin — and that IS deterministic, so it is
asserted at eval time in [`../checks/clients-eval.nix`](../checks/clients-eval.nix) rather than
here.

If something in here turns out to matter in a different way, distil the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
