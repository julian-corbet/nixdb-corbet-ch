#
# NixOS backend for the client catalogue. Here the system IS nix, so installing the clients into
# `environment.systemPackages` is correct rather than a duplication of a distro package manager.
#
# THE CLUSTER SIDE IS NOT HERE AND WILL NOT BE. `nixdb.operators` / `nixdb.instances` /
# `nixdb.tools` render Kubernetes objects through a nixidy evaluation, which is a different module
# system with a different set of options; a NixOS host composing this file gets the client surface
# and nothing else. That is the boundary rather than a gap -- see ./cluster.nix.
#
# EVERY ATTRIBUTE IS FORCE-EVALUATED, not merely looked up, and the reason is measured rather than
# theoretical: nixpkgs converts a renamed package into `<oldName> = throw "renamed to ...";`, which
# keeps the key present and only fails when the value is forced -- which is exactly what building
# `environment.systemPackages` does. This catalogue contains two names that behave that way (see
# ../studies/mariadb-client-and-mysql-client-both-throw.md), so an existence check here would ship
# a host configuration that evaluates and then fails to build. `tryEval` turns a stale mapping into
# a skip plus a warning instead of taking the whole system evaluation down: ../lib/clients.nix is a
# data table, and one stale row in it should not be able to make a machine unbuildable.
{ config, lib, pkgs, ... }:
let
  cfg = config.nixdb.clients;

  resolve = t: lib.getAttrFromPath (lib.splitString "." t.nixpkgs) pkgs;

  evaluated = map
    (t: { inherit t; try = builtins.tryEval (builtins.seq (resolve t) true); })
    cfg.selected;

  installable = map (r: r.t) (lib.filter (r: r.try.success) evaluated);
  stale = lib.filter (r: !r.try.success) evaluated;
in
{
  imports = [ ./clients.nix ];

  config = {
    environment.systemPackages = lib.unique (map resolve installable);

    warnings =
      map
        (r: "nixdb: nixpkgs attribute `${r.t.nixpkgs}` (catalogue entry `${r.t.name}`, pacman name `${r.t.arch}`) no longer resolves -- lib/clients.nix's mapping is stale, most likely a nixpkgs rename. The client was NOT installed.")
        stale
      ++ map
        (t: "nixdb: `${t.name}` installs the engine's SERVER binaries on NixOS as well as its client, because nixpkgs ships them in one derivation where Arch splits them into two packages. Nothing is started -- no service, no user, no data directory -- but the server commands are on PATH here and are not on an Arch host running the same selection. See lib/clients.nix's own entry.")
        (lib.filter (t: t.installsServerOnNixos or false) installable);
  };
}
