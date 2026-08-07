# The SQLite entry is the shell, and on nixpkgs the shell that works is `sqlite-interactive`

**Finding.** "SQLite" names a library and a command-line shell, and a catalogue of database
*clients* wants the shell — `sqlite3`. Arch ships both in one package, `core/sqlite`, so the
obvious name is right there. nixpkgs also ships both under `pkgs.sqlite`, and the obvious name is
*almost* right there: that build passes `--disable-readline`, so its `sqlite3` has no line editing,
no history and no arrow keys. `pkgs.sqlite-interactive` is the same package built with
`interactive = true`, and it is the entry.

The catalogued pair is therefore `arch = "sqlite"` / `nixpkgs = "sqlite-interactive"`, binary
`sqlite3` — see the `sqlite` entry in [`../lib/clients.nix`](../lib/clients.nix).

## Why it matters

This is the failure mode a name check cannot see, because nothing fails. Both attributes exist,
both force, both install a binary called `sqlite3`, both answer `.version` identically, and both
run any script you hand them. `pkgs.sqlite` is not a library-only derivation hiding its CLI behind
an output nobody installs — its `bin` output really does carry `bin/sqlite3` and
`meta.outputsToInstall` really does name that output. Every mechanical check this repository runs
passes on the wrong name.

What differs is the interactive session, which is the entire reason a person installs a database
shell rather than linking a library. The bare build gives a prompt where the up arrow prints
`^[[A`, backspace may not erase, and there is no history between statements. Arch's own package
links `libreadline` and `libncursesw` unconditionally, so declaring the bare pair would have
promised one capability on one platform and a materially worse one on the other — under one
catalogue entry, with one selection, which is exactly the asymmetry this catalogue exists to
prevent.

## Evidence

nixpkgs, 2026-08-08, pinned revision. The flag comes from the derivation itself
(`pkgs/development/libraries/sqlite`), whose `interactive ? false` argument decides between
`--disable-readline` and a build with readline and ncurses in `buildInputs`;
`sqlite-interactive` is that same derivation applied with `interactive = true`.

```
$ nix eval --raw nixpkgs#sqlite-interactive.name
sqlite-interactive-3.53.3
$ ls …-sqlite-interactive-3.53.3/bin
sqlite3
```

Upstream Arch, from its own package file list rather than a local mirror
(`https://archlinux.org/packages/core/x86_64/sqlite/files/json/`):

| Package | Version | Executables in `usr/bin/` |
|---|---|---|
| `sqlite` (`core`) | 3.53.4 | `dbdump dbhash dbtotxt index_usage showdb showjournal showshm showstat4 showwal sqldiff` **`sqlite3`** `sqlite3_expert sqlite3_rsync` |

One package, library and thirteen binaries, readline linked. There is no client-only Arch package
to prefer and — unlike the Postgres entry, which this is the mirror image of — no server to
accidentally install, so the asymmetry costs nothing and needs no `installsServerOnNixos` flag.
`meta.homepage` and pacman's `URL` are both `https://www.sqlite.org/`.

## What it changed

1. It settled which of two things called "sqlite" the catalogue means: the shell. A `file` client,
   because it opens a database on disk with no server, no port and no connection string — the
   group that exists for exactly that shape.
2. `checks/clients-eval.nix` asserts by name that the NixOS plane publishes `sqlite-interactive`
   and never the bare `sqlite`. A build-variant choice is invisible to every other check in this
   repository — both names resolve, both install `sqlite3` — so the only thing that can hold it is
   an assertion that says so.
3. It is the second reason the verification contract inspects the **command surface** rather than
   stopping at the name and the homepage. Here the surface is identical between the two candidates
   and the difference is in how the binary was linked, which is one step past what even that check
   can see: the correct name has to be recorded, with its reason, because nothing automated will
   rediscover it.
