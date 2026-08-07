# Evaluates modules/clients.nix for real against `lib.evalModules` and asserts what it resolves,
# plus the integrity of BOTH catalogues and the cross-reference between them.
#
# Here for the reason every sibling states for its own version of this file: `nix flake check` does
# not evaluate `nixosModules`/`systemManagerModules` on its own, so a green check on this repository
# without it would prove nothing but flake syntax.
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell. Every question this file
# can answer is a question about NAMES and LISTS -- which group a key belongs to, which side of the
# pacman/AUR split a name lands on, whether an engine's catalogued client speaks that engine's
# protocol -- and none of them needs a package set.
#
# What can NOT be proven here, and is not pretended: whether a name is in a given repository today,
# and whether a nixpkgs attribute still resolves. Those are facts about the world that change
# without this repository changing, and they are verified out of band against live sources -- see
# ../experiments/verify-package-names.sh.
{ pkgs, lib ? pkgs.lib }:
let
  clients = import ../lib/clients.nix { };
  engines = import ../lib/engines.nix { };

  evalWith = selection: (lib.evalModules {
    modules = [ ../modules/clients.nix { nixdb.clients = selection; } ];
  }).config.nixdb.clients;

  allWire = lib.attrNames clients.wire;
  allOperator = lib.attrNames clients.operator;
  allSelectable = lib.length allWire + lib.length allOperator;

  everything = evalWith { wire = allWire; operator = allOperator; };
  empty = evalWith { };

  entries = lib.concatMap (g: lib.attrValues clients.${g}) (lib.attrNames clients);

  has = list: item: lib.elem item list;
  sorted = lib.sort (a: b: a < b);

  results = {
    # ── The floor: nothing selected must produce nothing at all ────────────────────────────────
    "an empty selection resolves to nothing selected" =
      empty.selected == [ ];

    "an empty selection produces empty lists on EVERY plane, not one populated by default" =
      empty.archPackages == [ ] && empty.aurPackages == [ ]
      && empty.nixosPackages == [ ] && empty.binaries == { };

    # ── THE LOAD-BEARING INVARIANT ────────────────────────────────────────────────────────────
    # One AUR name reaching a pacman list aborts the entire pacman transaction with "target not
    # found" and takes every unrelated package in the same converge down with it.
    "archPackages and aurPackages never intersect -- the whole-transaction abort this split exists to prevent" =
      lib.intersectLists everything.archPackages everything.aurPackages == [ ];

    "every selection lands on exactly one of the two Arch lists -- none silently dropped, none counted twice" =
      lib.length (everything.archPackages ++ everything.aurPackages) == allSelectable;

    "the two AUR entries are on the AUR side and the two repository entries are on the pacman side" =
      sorted everything.aurPackages == [ "kubectl-cnpg" "mongosh-bin" ]
      && sorted everything.archPackages == [ "mariadb-clients" "postgresql-libs" ];

    # ── Group wiring ──────────────────────────────────────────────────────────────────────────
    "every catalogue group has a matching selection option on the module" =
      lib.all (g: empty ? ${g}) (lib.attrNames clients);

    "every group contributes: selecting the whole catalogue resolves every entry" =
      lib.length everything.selected == allSelectable;

    "each group's option is typed to its OWN keys -- an operator plugin is refused as a wire client" =
      # `evalModules` is lazy: `tryEval` alone forces only WHNF. `deepSeq` forces through, which is
      # what actually runs the listOf-enum merge that rejects the name.
      (builtins.tryEval (builtins.deepSeq (evalWith { wire = [ "kubectl-cnpg" ]; }).wire true)).success == false;

    "and the other way round -- a wire client is refused as an operator selection" =
      (builtins.tryEval (builtins.deepSeq (evalWith { operator = [ "psql" ]; }).operator true)).success == false;

    # ── Package name vs command name ──────────────────────────────────────────────────────────
    # Every entry in this catalogue disagrees with itself on at least one platform. A consumer
    # aliasing, wrapping or launching by the PACKAGE name gets a command that does not exist.
    "binaries maps every selection to its real command, not its package name" =
      everything.binaries == {
        psql = "psql";
        mariadb = "mariadb";
        mongosh = "mongosh";
        kubectl-cnpg = "kubectl-cnpg";
      };

    "the Postgres client's pacman name is a LIBRARY package and its command is not -- the entry's whole point" =
      has everything.archPackages "postgresql-libs"
      && !(has everything.archPackages "postgresql")
      && everything.binaries.psql == "psql";

    "the Mongo shell's AUR package carries a suffix its command does not" =
      has everything.aurPackages "mongosh-bin"
      && everything.binaries.mongosh == "mongosh";

    "binaries covers exactly the selection, no more -- an unselected entry contributes no command" =
      (evalWith { wire = [ "psql" ]; }).binaries == { psql = "psql"; };

    "the nixpkgs plane keeps the nested attribute path intact -- flattening it would name a THROWING attribute" =
      has everything.nixosPackages "mariadb.client"
      && !(has everything.nixosPackages "mariadb-client")
      && !(has everything.nixosPackages "mariadb");

    # ── Catalogue integrity ───────────────────────────────────────────────────────────────────
    "every catalogue entry names a package on BOTH platforms and the command it installs" =
      lib.all
        (t: lib.isString t.arch && lib.isString t.nixpkgs && lib.isString t.binary && t.arch != "" && t.nixpkgs != "")
        entries;

    "no two entries resolve to the same pacman name or the same nixpkgs attribute" =
      lib.length (lib.unique (map (t: t.arch) entries)) == lib.length entries
      && lib.length (lib.unique (map (t: t.nixpkgs) entries)) == lib.length entries;

    # ── THE CROSS-REFERENCE BETWEEN THE TWO CATALOGUES ────────────────────────────────────────
    # The cluster catalogue names a client for every engine and every operator. That reference is
    # the one thing in either file that can rot silently -- a renamed client key, or a client
    # quietly repointed at another protocol, changes nothing that any other check would notice.
    "every engine names a client that exists, and it speaks that engine's protocol" =
      lib.all
        (e: e.client != null -> (clients.wire ? ${e.client} && clients.wire.${e.client}.speaks == e.wire))
        (lib.attrValues engines.engines);

    "every operator names a control-plane client that exists, and it drives THAT operator" =
      lib.all
        (name:
          let o = engines.operators.${name}; in
          o.client != null -> (clients.operator ? ${o.client} && clients.operator.${o.client}.operates == name))
        (lib.attrNames engines.operators);

    "no orphan wire client: every protocol this catalogue ships a shell for is spoken by an engine the tier can run" =
      lib.all
        (c: lib.any (e: e.wire == c.speaks) (lib.attrValues engines.engines))
        (lib.attrValues clients.wire);

    "no orphan operator client: every plugin drives an operator the tier can run" =
      lib.all (c: engines.operators ? ${c.operates}) (lib.attrValues clients.operator);

    # The multi-model engine speaks a protocol that is not its own product, so it shares a client
    # with the engine that invented it. Pinned here because it looks like a copy-paste error and is
    # not -- see that entry's own note.
    "two different engines share one wire client, on purpose" =
      engines.engines.postgres.client == "psql"
      && engines.engines.arcadedb.client == "psql"
      && engines.engines.arcadedb.wire == "postgres";

    # ── The asymmetry the NixOS backend warns about ───────────────────────────────────────────
    "exactly one entry declares that its nixpkgs attribute also installs the engine's server" =
      lib.length (lib.filter (t: t.installsServerOnNixos or false) entries) == 1
      && clients.wire.psql.installsServerOnNixos;
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
