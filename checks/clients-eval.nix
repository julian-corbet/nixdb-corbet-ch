# Evaluates modules/clients.nix for real against `lib.evalModules` and asserts what it resolves,
# plus the integrity of both catalogues and the direction of the reference between them.
#
# Here for the reason every sibling states for its own version of this file: `nix flake check` does
# not evaluate `nixosModules`/`systemManagerModules` on its own, so a green check on this repository
# without it would prove nothing but flake syntax.
#
# ── WHAT THIS FILE CAN AND CANNOT PROVE WHILE THE CLIENT CATALOGUE IS EMPTY ────────────────────
#
# The catalogue ships with no entries, deliberately (see ../lib/clients.nix's own header: which
# package belongs to which repository is assigned, not decided here). That has an honest
# consequence which is stated rather than hidden: several invariants below hold over an EMPTY SET
# and therefore prove nothing today. They are written anyway, because they are the contract the
# first entry has to meet, and because a `lib.all` written now is correct the moment there is
# something to quantify over.
#
# What IS proven today, and is not vacuous:
#
#   - the whole resolution path exists and terminates: an empty selection resolves to nothing on
#     every plane the backends read, rather than to an error or to a default nobody asked for;
#   - both groups are declared, so the surface a future assignment lands on is real;
#   - NOTHING IS SELECTABLE. A selection into either group is refused at eval, which is the
#     mechanical form of "this repository claims no package yet";
#   - the cluster catalogue does not reference the client catalogue at all, in either direction of
#     naming -- the one property that would otherwise break the cluster side every time a package
#     moved between repositories.
#
# And there is a TRIPWIRE: the emptiness itself is asserted. The day a package is assigned here,
# this check fails and whoever adds it has to come back and un-vacuum the invariants below. That is
# deliberate — a check that silently starts covering a real catalogue with assertions written for
# an empty one is worse than no check.
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell. Every question here is a
# question about NAMES and LISTS. Whether a name is in a repository today, and whether a nixpkgs
# attribute still forces, are facts about the world that change without this repository changing --
# see ../experiments/verify-package-names.sh.
{ pkgs, lib ? pkgs.lib }:
let
  clients = import ../lib/clients.nix { };
  engines = import ../lib/engines.nix { };

  evalWith = selection: (lib.evalModules {
    modules = [ ../modules/clients.nix { nixdb.clients = selection; } ];
  }).config.nixdb.clients;

  empty = evalWith { };

  groups = lib.attrNames clients;
  entries = lib.concatMap (g: lib.attrValues clients.${g}) groups;

  # `evalModules` is lazy: `tryEval` alone forces only WHNF (the attrset exists), never the
  # type-checked value inside. `deepSeq` forces through, which is what actually runs the
  # listOf-enum merge that rejects a name.
  refuses = selection: group:
    (builtins.tryEval (builtins.deepSeq (evalWith selection).${group} true)).success == false;

  engineEntries = lib.attrValues engines.engines;
  operatorEntries = lib.attrValues engines.operators;
  clusterEntries = engineEntries ++ operatorEntries ++ lib.attrValues engines.tooling;

  results = {
    # ── The floor, and it is not vacuous: the whole path resolves ──────────────────────────────
    "an empty selection resolves to nothing selected" =
      empty.selected == [ ];

    "an empty selection produces empty lists on EVERY plane, not one populated by default" =
      empty.archPackages == [ ] && empty.aurPackages == [ ]
      && empty.nixosPackages == [ ] && empty.binaries == { };

    "every plane a backend reads is actually published, so an assignment needs no new option" =
      lib.all (o: empty ? ${o})
        [ "selected" "archPackages" "aurPackages" "nixosPackages" "binaries" ];

    # ── The surface exists, and claims nothing ────────────────────────────────────────────────
    "every catalogue group has a matching selection option on the module" =
      lib.all (g: empty ? ${g}) groups;

    "both kinds of client have a group, so neither has to be invented later" =
      lib.sort (a: b: a < b) groups == [ "operator" "wire" ];

    # THE CLAIM, ASSERTED MECHANICALLY. Not "the list happens to be empty" but "nothing can be
    # selected", which is what an empty enum gives and what makes the emptiness enforceable.
    "nothing is selectable in the wire group -- the surface is declared and claims no package" =
      refuses { wire = [ "anything" ]; } "wire";

    "nothing is selectable in the operator group either" =
      refuses { operator = [ "anything" ]; } "operator";

    # ── THE TRIPWIRE ──────────────────────────────────────────────────────────────────────────
    # Assignment is not this repository's decision, so an entry appearing here is a real event and
    # must not slip in under assertions that were written for an empty shelf.
    "the client catalogue is still empty, so the invariants below are known-vacuous -- when the first package is assigned, UPDATE THIS FILE rather than letting it pass by covering nothing" =
      entries == [ ];

    # ── The contract the first entry has to meet (vacuous today, by construction correct) ──────
    # THE LOAD-BEARING INVARIANT once anything is catalogued: one AUR name reaching a pacman list
    # aborts the entire pacman transaction with "target not found" and takes every unrelated
    # package in the same converge down with it.
    "archPackages and aurPackages can never intersect" =
      let everything = evalWith (lib.genAttrs groups (g: lib.attrNames clients.${g})); in
      lib.intersectLists everything.archPackages everything.aurPackages == [ ]
      && lib.length (everything.archPackages ++ everything.aurPackages) == lib.length entries;

    "every entry names a package on BOTH platforms and the command it installs" =
      lib.all
        (t: lib.isString (t.arch or null) && lib.isString (t.nixpkgs or null)
          && lib.isString (t.binary or null) && t.arch != "" && t.nixpkgs != "")
        entries;

    "no two entries resolve to the same pacman name or the same nixpkgs attribute" =
      lib.length (lib.unique (map (t: t.arch) entries)) == lib.length entries
      && lib.length (lib.unique (map (t: t.nixpkgs) entries)) == lib.length entries;

    "a wire client speaks a protocol some engine in the cluster catalogue actually runs" =
      lib.all (c: lib.any (e: e.wire == c.speaks) engineEntries) (lib.attrValues clients.wire);

    "an operator client drives an operator the cluster catalogue actually knows" =
      lib.all (c: engines.operators ? ${c.operates}) (lib.attrValues clients.operator);

    # ── THE DIRECTION OF THE REFERENCE, and this one is NOT vacuous ───────────────────────────
    # The cluster catalogue names protocols and operator keys; it must never name a PACKAGE. If it
    # did, every reassignment of a package to another repository would break the engines here --
    # and packages get reassigned by somebody who is not reading this file.
    "no cluster catalogue entry names a client package, in any group" =
      lib.all (e: !(e ? client) && !(e ? clientPackage) && !(e ? arch)) clusterEntries;

    "every engine still records the PROTOCOL a client would speak to it, which is the reference that survives a package moving" =
      lib.all (e: lib.isString (e.wire or null) && e.wire != "") engineEntries;

    "and every operator still records what it manages, so an operator client has something to point back at" =
      lib.all (o: lib.isList (o.manages or null) && o.manages != [ ]) operatorEntries;

    # The multi-model engine speaks a protocol that is not its own product. Pinned because it looks
    # like a copy-paste error and is not -- see that entry's own note.
    "two different engines record the same wire protocol, on purpose" =
      engines.engines.arcadedb.wire == engines.engines.postgres.wire;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixdb: clients-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
