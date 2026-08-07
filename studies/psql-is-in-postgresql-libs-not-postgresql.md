# `psql` is in `postgresql-libs`, not `postgresql` — and nixpkgs does not split them at all

**Finding.** On upstream Arch, the interactive PostgreSQL terminal `psql` is shipped by the package
named `postgresql-libs`. The package named `postgresql` is the **server** and contains no `psql`.
nixpkgs makes no such split: `pkgs.postgresql` is one derivation carrying the client and the server
together, and the obvious client-only alternative, `pkgs.libpq`, ships no executables at all.

**This package is not catalogued here.** Which repository owns a Postgres client is an assignment
its operator makes, and it has not been made — see [`../lib/clients.nix`](../lib/clients.nix). What
the finding decided is what the *surface* has to be able to express: the `installsServerOnNixos`
field exists and the NixOS backend warns from it, because the two platforms genuinely do not
install the same thing and no wording in a comment can fix that. If and when the package is
assigned here, the pair is `arch = "postgresql-libs"` / `nixpkgs = "postgresql"` and the trap below
is already mapped.

## Why it matters

Guessing the Arch name from the project name is wrong in the one direction that is not obviously
wrong. `pacman -S postgresql` succeeds, reports a package installed, and leaves the command that
was wanted missing — while adding a database server, a system user and a service unit to a machine
that was only supposed to gain a shell.

The reverse guess is wrong too, and quieter. Reading "libs" as "the shared library, no binaries"
and reaching for what looks like the client package would have found no such package: on Arch there
is no third package, and in nixpkgs the name that *does* mean "just the library" (`libpq`) really
does mean it.

## Evidence

Package file lists, read from upstream Arch's own API rather than from a local mirror
(`https://archlinux.org/packages/extra/x86_64/<pkg>/files/json/`), 2026-08-07:

| Package | Version | Executables in `usr/bin/` |
|---|---|---|
| `postgresql-libs` | 18.4 | `clusterdb createdb createuser dropdb dropuser ecpg pg_config pg_dump pg_dumpall pg_isready pg_restore` **`psql`** `reindexdb vacuumdb vacuumlo` |
| `postgresql` | 18.4 | `initdb oid2name pg_amcheck pg_archivecleanup pg_basebackup pg_checksums pg_combinebackup pg_controldata pg_createsubscriber pg_ctl pg_receivewal pg_recvlogical pg_resetwal pg_rewind pg_test_fsync pg_test_timing pg_upgrade pg_verifybackup pg_waldump pg_walsummary pgbench postgres postgresql-check-db-dir` |

Both are in upstream Arch's `extra` repository, both x86_64, so neither is an AUR question.

nixpkgs, realized from the pinned revision and listed rather than inferred:

| Attribute | Derivation | `bin/` |
|---|---|---|
| `pkgs.postgresql` | `postgresql-18.4` | `psql` **and** `postgres`, `initdb`, `pg_ctl`, `pg_upgrade`, … (34 entries) |
| `pkgs.libpq` | `libpq-18.4` | *no `bin/` directory at all* |

`meta.homepage` on the nixpkgs side and `URL` on the pacman side are both
`https://www.postgresql.org`, so the cross-check that catches a pair pointing at two different
projects passes — this is one project, split two ways by one packager and not by the other.

## What it changed

1. `installsServerOnNixos` exists as a **field** rather than a sentence in a comment, and
   `modules/nixos.nix` warns from it at evaluation time. The asymmetry cannot be removed — there is
   no client-only attribute to switch to — so the honest answer is to say so where somebody will
   read it. That is the one part of this finding that is already built.
2. It is the reason the verification contract cross-checks the **command surface** at all, and not
   only the package name and the homepage. Two names can agree on the project and the version and
   still install different commands; here they agree on everything and one of them installs a
   database server.
3. It records, for whoever assigns the package, that the obvious name is wrong in the expensive
   direction: `pacman -S postgresql` succeeds, reports a package installed, and leaves the wanted
   command missing while adding a database server to a workstation. A `pacman -Si postgresql` hit
   would have looked like confirmation.
