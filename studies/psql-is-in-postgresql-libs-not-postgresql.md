# `psql` is in `postgresql-libs`, not `postgresql` — and nixpkgs does not split them at all

**Finding.** On upstream Arch, the interactive PostgreSQL terminal `psql` is shipped by the package
named `postgresql-libs`. The package named `postgresql` is the **server** and contains no `psql`.
nixpkgs makes no such split: `pkgs.postgresql` is one derivation carrying the client and the server
together, and the obvious client-only alternative, `pkgs.libpq`, ships no executables at all.

Decided the catalogue entry to be `arch = "postgresql-libs"` / `nixpkgs = "postgresql"`, and
introduced the `installsServerOnNixos` field plus the warning the NixOS backend raises from it,
because the two platforms genuinely do not install the same thing.

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

1. The catalogue entry names `postgresql-libs`. A `pacman -Si` hit on `postgresql` would have looked
   like confirmation of the wrong name.
2. `installsServerOnNixos = true` exists as a field rather than a sentence in a comment, and
   `modules/nixos.nix` warns from it at evaluation time. The asymmetry cannot be removed — there is
   no client-only attribute to switch to — so the honest answer is to say so where somebody will
   read it.
3. It is the reason the catalogue's verification cross-checks the **command surface** at all, and
   not only the package name and the homepage. Two names can agree on the project and the version
   and still install different commands; here they agree on everything and one of them installs a
   database server.
