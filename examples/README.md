# examples

Placeholder values that make this repository's checks real, and the shortest readable answer to
"what does a declaration actually look like".

- [`all/values.nix`](all/values.nix) — one complete tier: an operator sitting below the instances it
  manages, a **ladder** (two majors of one engine, side by side and permanently), a self-managed
  engine on node-path state with its root credential by reference, a third engine whose wire
  protocol is not its own product, and tier tooling in its own namespace. `nix flake check` renders
  it through the real app grammar and the real renderer and then asserts the manifests field by
  field, so a module that stops evaluating — or that grows a required value nobody supplies — fails
  in CI rather than in somebody's cluster.

**Nothing in here is real.** Every namespace, node path, Secret name, image reference and slot
number is invented for the check. That is not a disclaimer, it is the design: every one of those is
a fleet fact, and this repository supplies none of them — see the main [README](../README.md).
