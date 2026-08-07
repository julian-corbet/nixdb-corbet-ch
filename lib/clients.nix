#
# The client catalogue: what a PERSON installs on a host in order to work with databases.
#
# ── IT IS EMPTY, AND THAT IS A STATE RATHER THAN AN OVERSIGHT ──────────────────────────────────
#
# Both groups below are declared and both are empty. Nothing here is a gap waiting to be filled in
# by whoever reads this file next: WHICH PACKAGE BELONGS TO WHICH REPOSITORY IS NOT A QUESTION
# THIS FILE GETS TO ANSWER. It is assigned, per package, by the person who owns the package set,
# and a catalogue that guessed would quietly take a package out of the repository that has it today
# — where it is already declared, already verified and already installed on real hosts.
#
# So the surface is built and the shelf is bare. ../modules/clients.nix resolves it, both host
# backends consume it, and ../checks/clients-eval.nix proves the whole path resolves an empty
# selection to nothing on every plane. Adding the first package is then one entry in this file and
# nothing else — which is the entire point of building the surface before there is anything to put
# on it.
#
# ── THE TWO GROUPS, AND WHY THEY ARE TWO ───────────────────────────────────────────────────────
#
#   `wire`      speaks one engine's wire protocol. A shell you point at a running database.
#   `operator`  drives an operator's control plane. Not a database client at all — it asks the
#               operator about the instances it manages, and tells it to do things to them. It
#               never opens a connection to a database, and a host may well want exactly one of
#               the two kinds.
#
# The split is by WHAT A TOOL IS, not by what it touches — the same test the universal terminal
# shelf applies to its own groups. A third kind is clearly out there and is deliberately not
# declared yet: an inspector that opens a database FILE with no server involved at all. That is a
# different thing again from both groups above, and declaring a group for it now would be
# machinery with nothing to decide, plus an implicit claim on packages nobody has assigned here.
#
# ── WHAT IS ALREADY SOMEWHERE ELSE ─────────────────────────────────────────────────────────────
#
# Named so that nobody re-derives it, and stated as WHERE THEY ARE rather than as where they
# belong — the difference matters, because the second is not this repository's call:
#
#   - the SQLite shell and the multi-engine terminal browsers are catalogued today in the
#     universal terminal-tool shelf, in its structured-data group. They are declared, verified and
#     installed from there.
#   - local database FILE inspectors — the ones that open a single embedded database on disk with
#     no server anywhere — are catalogued today in the development-tooling repository.
#   - engine wire shells and multi-engine command lines are, at the time of writing, catalogued
#     NOWHERE in this family.
#
# ONE PACKAGE, ONE CATALOGUE is the family rule, and it is why none of the above appears below: on
# a NixOS host every catalogue feeds the same package list, so a second entry for one package is a
# collision rather than a redundancy. Whether any of them should MOVE here one day is a decision
# for whoever assigns packages to repositories. This file records the boundary as it stands; it
# does not argue for redrawing it, and it must not be read as a claim in either direction.
#
# ── FIELDS, for the day there is an entry ──────────────────────────────────────────────────────
#
# Documented now rather than invented later, because the checks and both backends already consume
# them and every one of them exists for a measured reason:
#
# `arch`      the pacman package name.
# `aur`       (default false) the name lives in the AUR rather than an official Arch repository.
#             Load-bearing in one direction only, and fatally: `pacman -S` resolves a transaction
#             ATOMICALLY, so ONE AUR name in a pacman list fails the whole thing with "target not
#             found" and takes every unrelated package in the same converge down with it. The two
#             lists ../modules/clients.nix publishes are separate for exactly this reason, and
#             that they never intersect is asserted.
# `nixpkgs`   the nixpkgs attribute, as a dotted path for a nested one. A dotted path is the
#             expected shape rather than the exception here — see the studies.
# `binary`    the command it actually installs. NOT always the package name, and in this subject
#             usually not: of the four candidates verified so far (see below) not one matches its
#             own package name on both platforms.
# `speaks`    (`wire` group) the engine family this client's protocol belongs to, matching the
#             `wire` field of ../lib/engines.nix. THE REFERENCE POINTS THIS WAY ROUND on purpose:
#             an engine names a protocol, never a package, so the cluster catalogue cannot break
#             when a package is assigned somewhere else.
# `operates`  (`operator` group) the operator key this plugin drives, from ../lib/engines.nix.
# `installsServerOnNixos`
#             (default false) the nixpkgs attribute additionally installs the ENGINE's server
#             binaries, where the Arch package is client-only. Reserved rather than speculative:
#             it is measured, and ../studies/psql-is-in-postgresql-libs-not-postgresql.md is the
#             evidence — the asymmetry cannot be removed, because nixpkgs has no client-only
#             attribute to switch to. ../modules/nixos.nix warns from it.
# `note`      what the entry is, and every trap in getting it installed.
#
# ── THE VERIFICATION CONTRACT AN ENTRY MUST MEET ───────────────────────────────────────────────
#
# FOUR SOURCES, because no two of them answer the same question:
#
#   - `pacman -Si <name>` on a live Arch-derivative system. Says what a name resolves to HERE,
#     which is not the same as what upstream Arch ships. NEVER sufficient on its own.
#   - archlinux.org's package search API (`/packages/search/json/?name=<name>`), which IS upstream
#     Arch and knows nothing about a derivative's extra repositories. The only authority for
#     `aur = false`.
#   - the AUR RPC (`https://aur.archlinux.org/rpc/v5/info?arg[]=<name>`). The only authority for
#     `aur = true`.
#   - the nixpkgs attribute FORCED: `builtins.seq p.drvPath`. `hasAttrByPath` cannot distinguish a
#     live attribute from a rename-to-throw.
#
# Plus two cross-checks a name existing on both platforms cannot pass on its own: `meta.homepage`
# against pacman's `URL`, so a pair that resolves on both platforms while pointing at two DIFFERENT
# projects is caught; and THE COMMAND SURFACE, by listing `bin/` of the realized store path against
# the Arch package's own file list, because two names for the same project at the same version can
# install different commands.
#
# ../experiments/verify-package-names.sh runs all of it, reading the names out of THIS file.
#
# ── ALREADY VERIFIED, NOT YET CATALOGUED ───────────────────────────────────────────────────────
#
# Four likely candidates were put through the whole contract above on 2026-08-07, before it was
# settled that assignment is not this repository's to make. The results are kept — in
# ../studies/ — because they cost real time, they do not go stale quickly, and they make the
# assignment decision cheaper for whoever makes it. Two of the four are outright traps:
#
#   - the Postgres shell's Arch package is named for a LIBRARY, while the package named for the
#     project is the server and contains no shell at all; and nixpkgs makes no such split, so the
#     same selection installs a database server there. That is what `installsServerOnNixos` is for.
#   - both obvious nixpkgs attributes for the MySQL-protocol client exist and both THROW, and the
#     bare product attribute is the server. Only forcing the derivation finds any of it.
#
# Recording a finding is not claiming a package. Nothing below is declared.
{ ... }:
{
  # ── Wire clients: a shell for one engine's protocol ──────────────────────────────────────────
  wire = { };

  # ── Operator clients: drives an operator's control plane, not a database ─────────────────────
  operator = { };
}
