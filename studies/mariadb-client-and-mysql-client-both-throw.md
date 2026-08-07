# `mariadb-client` and `mysql-client` both exist in nixpkgs, and both throw

**Finding.** Two nixpkgs attributes name the MySQL-protocol client in the way anybody would guess.
Both are present as attributes, and both raise an error the moment their value is forced. The live
attribute is the nested `mariadb.client`.

Decided the catalogue entry to be `nixpkgs = "mariadb.client"`, and is the reason
`modules/nixos.nix` force-evaluates every attribute through `tryEval` instead of checking that it
exists.

## Why it matters

`lib.hasAttrByPath [ "mariadb-client" ] pkgs` returns `true`. So does an `?` test, and so does
anything else that only asks whether the key is present. nixpkgs implements a removal or a rename
as `<oldName> = throw "...";`, which keeps the key and only fails when the value is demanded —
which is exactly what building `environment.systemPackages` does, and nothing earlier.

The failure therefore lands as far from its cause as it can: a host configuration that evaluates
cleanly, passes whatever check the consumer runs, and fails at build time with an error about a
package the operator never wrote down.

## Evidence

Forced against the pinned revision, 2026-08-07:

```
$ nix eval --raw nixpkgs#mariadb-client.name
error: mariadb-client has been renamed to mariadb.client

$ nix eval --raw nixpkgs#mysql-client.name
error: mysql-client has been replaced by mariadb.client
```

Both errors come from the throw-alias table in nixpkgs' own aliases file, which is where every
removed and renamed attribute is parked. Neither is an "attribute missing" error — that is the
whole point.

The third guess is wrong in a different way and does not throw at all, which makes it the more
dangerous of the three:

```
$ nix eval --raw nixpkgs#mariadb.name
mariadb-server-11.4.12
```

`pkgs.mariadb` is the **server**. It builds, it installs, and it does not give you a client shell.

The live attribute, realized and listed rather than assumed:

```
$ nix build --no-link --print-out-paths nixpkgs#mariadb.client
/nix/store/…-mariadb-client-11.4.12
$ ls …-mariadb-client-11.4.12/bin
mariadb mariadb-admin mariadb-binlog … mysql mysqladmin mysqldump …
```

Both command names are present — the current `mariadb` and the compatibility `mysql` — which
matches the Arch package `mariadb-clients` (upstream `extra`, 12.3.2) file for file in the names
that matter. `meta.homepage` and pacman's `URL` are both `https://mariadb.org/`.

## What it changed

1. The catalogue keeps the **dotted path** `mariadb.client` rather than flattening it to something
   that reads more like the other entries, and `checks/clients-eval.nix` asserts that the flattened
   forms never appear on the resolved nixpkgs list.
2. `modules/nixos.nix` resolves every entry with `builtins.tryEval (builtins.seq …)` and downgrades
   a stale mapping to a warning plus a skip, instead of taking the whole system evaluation down.
   The catalogue is a data table; one stale row in it should not be able to make a machine
   unbuildable.
3. It is the reason this repository's package verification forces derivations at all. An existence
   check would have passed on two attributes in one file, in the same sitting, and shipped both.
