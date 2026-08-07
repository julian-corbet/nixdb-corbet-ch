#
# nixdb's client policy: the selection surface for ../lib/clients.nix, and the package-name lists a
# host's own reconciler consumes. Installs nothing itself.
#
# THIS MODULE IS ALSO THE ARCH BACKEND, and there is deliberately no second file behind
# `systemManagerModules.default`. Same conclusion the sibling repos reached once their platform-
# specific work moved elsewhere: on Arch there is nothing here to install FROM -- the lists below
# are published and the host's own pacman reconciler consumes them -- so an `arch.nix` whose entire
# body was `imports = [ ./clients.nix ];` would be a file that exists to be an indirection.
#
#   nixarch.packages.pacman = config.nixdb.clients.archPackages;
#   nixarch.packages.aur    = config.nixdb.clients.aurPackages;
#
# PUBLISHED, NOT WIRED, and that is a choice rather than an omission. This module could assign
# `nixarch.packages.*` directly. It does not, for the reason every catalogue repo in this family
# also does not: a host almost always concatenates several catalogues into one reconciler list, and
# a module that assigns into a FOREIGN namespace both hard-depends on that namespace existing and
# takes the concatenation point away from the one file that can see every catalogue at once.
#
# NO `distro` OPTION HERE, unlike some siblings, and the absence is deliberate rather than an
# unfinished corner. That option exists in a catalogue where an AUR-only name is carried by SOME
# Arch derivative's own repository, so which list an entry lands on depends on the host. Neither
# AUR entry in this catalogue has that property -- both were checked against a derivative's
# repositories and found in none -- so a `distro` option here would be machinery with nothing to
# decide, and a reader would reasonably assume it decided something.
#
# ONE NAMESPACE. Everything declared here lives under `nixdb`, like every repo in this family; the
# client surface is nested at `nixdb.clients` so it cannot collide with the cluster surface
# (`nixdb.operators` / `nixdb.instances` / `nixdb.tools`) that shares the namespace.
{ config, lib, ... }:
let
  cfg = config.nixdb.clients;
  cat = import ../lib/clients.nix { };

  mkGroup = what: table: lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames table));
    default = [ ];
    description = "Which ${what}. Available: ${lib.concatStringsSep ", " (lib.attrNames table)}.";
  };

  # Each resolved entry carries its own catalogue KEY back out as `name` -- without it, everything
  # downstream that needs to say WHICH selection a resolved attrset came from would have to
  # re-derive it by matching on `arch`, which is a different string for every entry in this
  # catalogue.
  resolve = table: k: table.${k} // { name = k; };

  # Groups are hand-listed rather than generated from `lib.attrNames cat`, matching the siblings.
  # The fragility that invites -- a group added to the catalogue and never wired into an option --
  # is closed by a check instead of by cleverness: ../checks/clients-eval.nix asserts that every
  # catalogue group has a matching option on this module.
  selected = lib.flatten [
    (map (resolve cat.wire) cfg.wire)
    (map (resolve cat.operator) cfg.operator)
  ];

  fromAur = t: t.aur or false;
in
{
  options.nixdb.clients = {
    wire = mkGroup
      "database wire-protocol clients -- a shell for one engine's protocol (see ../lib/clients.nix's own header for the boundary against the universal terminal-tool shelf, which already carries the engine-agnostic ones)"
      cat.wire;

    operator = mkGroup
      "operator control-plane clients -- these drive an operator, never a database, which is why they are their own group rather than more of `wire`"
      cat.operator;

    # ── Computed, read-only ─────────────────────────────────────────────────────────────────────
    selected = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      description = ''
        The resolved catalogue entries for every name selected above, in one flat list -- the
        canonical "what did this host actually ask for" that every backend derives from. Backends
        read THIS rather than re-deriving a selection from one platform's own package split: the
        pacman/AUR distinction is meaningless on NixOS, and filtering by it there would silently
        drop an entry.
      '';
    };

    archPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections that come from an official Arch repository, as pacman names. For the host's own
        reconciler:

          nixarch.packages.pacman = config.nixdb.clients.archPackages;
      '';
    };

    aurPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections that must be built from the AUR, kept SEPARATE from `archPackages` because
        `pacman -S` cannot resolve an AUR name: it fails the whole transaction with "target not
        found", taking every other package in the same converge with it. Wire to the AUR side of
        the same reconciler:

          nixarch.packages.aur = config.nixdb.clients.aurPackages;

        Non-empty means the host needs a working AUR helper (and, for an unattended reconciler,
        whatever non-root user and sudo rule that helper requires). Both of this catalogue's AUR
        entries are AUR on every Arch-family host, so any selection touching them is non-empty
        here -- if the host has no helper, prefer leaving the selection out over declaring
        something that will be reported as installed and will not exist.
      '';
    };

    nixosPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections as nixpkgs attribute paths (dotted for a nested attribute). Published for
        introspection; ../modules/nixos.nix is what actually resolves and installs them, and it
        force-evaluates each one rather than trusting that the attribute exists -- see that file.
      '';
    };

    binaries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = ''
        catalogue name -> the command actually installed, for every selection. Published because
        the two disagree for most of this catalogue, and because a consumer writing a wrapper, an
        alias or a launcher against the PACKAGE name gets a command that does not exist -- the
        Arch package for the Postgres shell is named for a library, and the one for the Mongo
        shell carries a suffix its command does not.
      '';
    };
  };

  config = {
    nixdb.clients.selected = selected;
    nixdb.clients.archPackages = lib.unique (map (t: t.arch) (lib.filter (t: !(fromAur t)) selected));
    nixdb.clients.aurPackages = lib.unique (map (t: t.arch) (lib.filter fromAur selected));
    nixdb.clients.nixosPackages = lib.unique (map (t: t.nixpkgs) selected);
    nixdb.clients.binaries =
      lib.listToAttrs (map (t: lib.nameValuePair t.name t.binary) selected);
  };
}
