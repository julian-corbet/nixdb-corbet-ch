# studies

Written-up findings: things that were checked in [`../experiments/`](../experiments/README.md),
turned out to matter, and are worth recording properly — with the reasoning, not just the result.

A study earns its place here once it changed a decision in the main project. See the main
[README](../README.md) for the project itself.

The first two below are about packages this repository **does not catalogue**. Which repository owns
a database client is an assignment its operator makes and it has not been made — see
[`../lib/clients.nix`](../lib/clients.nix). They are kept because they cost real time, they do not
go stale quickly, and each of them decided something about the *surface* that is already built.
Recording a finding is not claiming a package.

| File | Finding |
|---|---|
| `psql-is-in-postgresql-libs-not-postgresql.md` | On upstream Arch the `psql` binary ships in `postgresql-libs`; the package called `postgresql` is the **server** and contains no `psql` at all. nixpkgs makes no such split — `pkgs.postgresql` carries both halves in one derivation, and `pkgs.libpq` (the obvious client-only guess) has no `bin/` directory whatsoever. Introduced the `installsServerOnNixos` field and the warning the NixOS backend raises from it, and is why the verification contract cross-checks the command surface rather than only the package name and the homepage. |
| `mariadb-client-and-mysql-client-both-throw.md` | `pkgs.mariadb-client` and `pkgs.mysql-client` both exist as attributes and both throw when forced (renamed and replaced, respectively, to `mariadb.client`); `pkgs.mariadb` is the server, not the client. An existence check passes on all three. Is why `modules/nixos.nix` force-evaluates every attribute through `tryEval` rather than testing that it exists, and why the verification contract forces derivations at all. |
| `an-operator-managed-instance-is-not-a-deployment.md` | The app grammar this repository consumes renders a Deployment for every app unconditionally, from a required `image`, so it cannot express an Application carrying only passed-through objects — which is exactly what an operator's chart output and an operator-managed instance's custom resource are. Decided the two-route render, the `manifests` value, the countable `nixdb.renderedDirectly` report, and the guard that refuses a namespace anchored by a workload rendered below the grammar. |
