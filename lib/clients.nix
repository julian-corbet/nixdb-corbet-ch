#
# The client catalogue: what a PERSON installs on a host in order to talk to the tier. Two groups,
# matching the two kinds of thing the cluster catalogue holds:
#
#   `wire`      speaks one engine's wire protocol. A shell you point at a running database.
#   `operator`  drives an operator's control plane. Not a database client at all -- it asks the
#               operator about the instances it manages, and tells it to do things to them.
#
# THE PLACEMENT RULE, and the reason this catalogue is small:
#
#   Does the tool speak ONE engine's protocol (or drive ONE operator), so that a host with none of
#   that engine has no use for it?
#     yes -> here
#     no  -> the universal terminal-tool shelf (nixsh), which is where anything a host reaches for
#            regardless of what it runs already lives
#
# CONSIDERED AND EXCLUDED, named rather than silently left out so the next candidate is decidable:
#
#   - the SQLite shell. Engine-specific by the letter of the rule and universal by every other
#     measure: it opens a file, needs no server, and is how half the services on any host are
#     actually debugged. It is already catalogued on the universal shelf, and this family's
#     one-package-one-catalogue rule makes a second entry a collision rather than a redundancy --
#     both feed the same package list on a NixOS host.
#   - multi-engine TUIs and universal SQL command lines. They speak every protocol, which is
#     exactly the property that fails the rule above: a host with no databases at all still has a
#     use for one. Same shelf, same reasoning, and one of them is already catalogued there.
#   - third-party enhanced REPLs for a single engine (auto-completion, syntax highlighting).
#     Eligible by the rule -- they do speak exactly one protocol -- and deliberately not catalogued
#     yet. What this catalogue holds is the shell the ENGINE ITSELF ships, the one every upstream
#     document assumes you are typing into, one per protocol family. That is a scope decision, not
#     a boundary one, and an entry may be added the day somebody actually wants it.
#
# ── FIELDS ─────────────────────────────────────────────────────────────────────────────────────
#
# `arch`      the pacman package name.
# `aur`       (default false) the name lives in the AUR rather than an official Arch repository.
#             Load-bearing in one direction only, and fatally: `pacman -S` resolves a transaction
#             ATOMICALLY, so ONE AUR name in a pacman list fails the whole thing with "target not
#             found" and takes every unrelated package in the same converge down with it. The two
#             lists ../modules/clients.nix publishes are separate for exactly this reason, and that
#             they never intersect is asserted.
# `nixpkgs`   the nixpkgs attribute, as a dotted path for a nested one.
# `binary`    the command it actually installs. NOT always the package name -- see every entry
#             below, none of which matches its own package name on both platforms.
# `speaks`    (`wire` group) the engine family this client's protocol belongs to. Cross-checked
#             against ./engines.nix: an engine naming a client that speaks something else fails
#             `nix flake check`.
# `operates`  (`operator` group) the operator key this plugin drives, cross-checked the same way.
# `installsServerOnNixos`
#             (default false) the nixpkgs attribute additionally installs the ENGINE's server
#             binaries, where the Arch package is client-only. Exactly one entry needs it, and it
#             is a field rather than a sentence in a note because ../modules/nixos.nix warns about
#             it at eval time.
# `note`      what the entry is, and every trap in getting it installed.
#
# ── VERIFIED, NOT GUESSED ──────────────────────────────────────────────────────────────────────
#
# Every pair below was checked on 2026-08-07 against FOUR independent sources, because no two of
# them answer the same question and three of the four entries were wrong under at least one naive
# guess:
#
#   - `pacman -Si <name>` on a live Arch-derivative system. Says what a name resolves to HERE,
#     which is not the same as what upstream Arch ships.
#   - archlinux.org's package search API (`/packages/search/json/?name=<name>`), which IS upstream
#     Arch and knows nothing about a derivative's extra repositories. The only authority for
#     `aur = false`.
#   - the AUR RPC (`https://aur.archlinux.org/rpc/v5/info?arg[]=<name>`). The only authority for
#     `aur = true`.
#   - the nixpkgs attribute FORCED, not merely looked up: `builtins.seq p.drvPath`. `hasAttrByPath`
#     cannot distinguish a live attribute from a rename-to-throw, and this catalogue found two of
#     those in one sitting -- see ../studies/mariadb-client-and-mysql-client-both-throw.md.
#
# Plus two cross-checks that a name existing on both platforms cannot pass on its own:
#
#   - `meta.homepage` against pacman's `URL`, so a pair that resolves on both platforms while
#     pointing at two DIFFERENT projects is caught rather than assumed correct.
#   - THE COMMAND SURFACE, by listing `bin/` of the realized store path against the Arch package's
#     own file list. Two names for the same project at the same version can install different
#     commands, and the pair that looks most correct by homepage is exactly where that hides. Half
#     the entries below carry a finding that only this cross-check produces.
#
# ../experiments/verify-package-names.sh reproduces all of it, reading the names out of THIS file
# rather than a second hand-kept list.
{ ... }:
{
  # ── Wire clients: a shell for one engine's protocol ──────────────────────────────────────────
  wire = {
    psql = {
      arch = "postgresql-libs";
      nixpkgs = "postgresql";
      binary = "psql";
      speaks = "postgres";
      installsServerOnNixos = true;

      note = ''
        PostgreSQL's own interactive terminal. Also the client for anything speaking the Postgres
        wire protocol, which in this catalogue includes the multi-model engine.

        THE ARCH PACKAGE IS `postgresql-libs`, NOT `postgresql`, and getting this wrong is the
        loudest trap in the file. Upstream Arch splits the project the way a distribution does:
        `postgresql` is the SERVER (initdb, postgres, pg_ctl, pg_upgrade -- and no psql at all),
        while `postgresql-libs` carries libpq and the client binaries, psql among them. Installing
        the obvious name on a workstation therefore installs a database server, adds a system user
        and a service, and still leaves the command that was wanted missing. Verified from the
        package file lists rather than assumed -- see
        ../studies/psql-is-in-postgresql-libs-not-postgresql.md.

        NIXPKGS DOES NOT MAKE THAT SPLIT, and the asymmetry is real rather than cosmetic.
        `pkgs.postgresql` is one derivation carrying the client AND the server in the same `out`
        (verified by listing `bin/`: psql sits beside postgres, initdb and pg_ctl), so selecting
        this entry on NixOS puts server binaries on PATH that the Arch host will not have.
        `installsServerOnNixos` records that, and ../modules/nixos.nix warns rather than leaving
        it to be discovered.

        AND THERE IS NO CLIENT-ONLY ALTERNATIVE TO REACH FOR. `pkgs.libpq` exists and is the
        obvious guess -- it is the C library and nothing else: the realized path has no `bin/`
        directory at all. It cannot substitute here.
      '';
    };

    mariadb = {
      arch = "mariadb-clients";
      nixpkgs = "mariadb.client";
      binary = "mariadb";
      speaks = "mysql";

      note = ''
        MariaDB's own client, which is also the client for anything speaking the MySQL protocol.
        Installs BOTH commands: `mariadb` (the current name) and `mysql` (the compatibility name),
        on both platforms -- confirmed by listing `bin/` on the realized nixpkgs path and the Arch
        package's file list, which agree. Scripts written against either name keep working.

        THE NIXPKGS ATTRIBUTE IS NESTED, and both flat guesses are booby-trapped. `mariadb-client`
        and `mysql-client` each exist as attributes and each THROWS when evaluated -- one says it
        was renamed, the other that it was replaced, both pointing at `mariadb.client`. An
        existence check passes on either and the build then fails; only forcing the derivation
        finds it. Written up in
        ../studies/mariadb-client-and-mysql-client-both-throw.md, because it is the exact failure
        mode this catalogue's verification exists to catch.

        The bare `mariadb` attribute is not this: it is the SERVER (its derivation is literally
        named mariadb-server). `mariadb.client` is a separate output of the same source.

        THE TWO PLATFORMS ARE ON DIFFERENT MAJORS, which is a fact about the distributions rather
        than a mistake here, and harmless for a client: the wire protocol is stable across these
        majors in both directions, and a newer client talks to an older server routinely.
      '';
    };

    mongosh = {
      arch = "mongosh-bin";
      aur = true;
      nixpkgs = "mongosh";
      binary = "mongosh";
      speaks = "mongodb";

      note = ''
        MongoDB's current shell -- a JavaScript REPL against a running instance, and the only
        client the engine's own documentation assumes.

        AUR, EVERYWHERE, AND NOT BY OVERSIGHT. Upstream Arch packages nothing MongoDB at all: the
        search API returns zero results for this name and for the database itself, because the
        project's licence took it out of the official repositories years ago and it has not come
        back. `pacman -Si` finds it in no derivative repository either, so unlike an entry that is
        AUR upstream and repository-provided on a derivative, there is nothing to lift here: this
        is the whole answer on every Arch-family host.

        `-bin` IS THE ENTRY, and the choice is deliberate rather than incidental. Two AUR packages
        build this shell: one compiles it and one installs the vendor's own build. The vendor build
        is the far better maintained of the two (about six times the votes) and is what upstream
        ships anyway -- this is a Node application whose from-source build has no advantage to
        offer. The package name carries the `-bin` suffix; the command it installs does not.

        Both platforms are on the same version, and the AUR package's upstream URL and the nixpkgs
        homepage resolve to the same project.
      '';
    };
  };

  # ── Operator clients: drives an operator's control plane, not a database ─────────────────────
  operator = {
    kubectl-cnpg = {
      arch = "kubectl-cnpg";
      aur = true;
      nixpkgs = "kubectl-cnpg";
      binary = "kubectl-cnpg";
      operates = "cnpg";

      note = ''
        The PostgreSQL operator's own kubectl plugin: reports on the instances it manages, and
        performs the operations that must go through the operator rather than around it --
        promoting a replica, requesting a switchover, restarting an instance, collecting a support
        bundle.

        NOT A DATABASE CLIENT, which is why it is in its own group. It never opens a connection to
        Postgres; it talks to the Kubernetes API and to the operator. A host that runs the psql
        entry above and this one is doing two unrelated things, and a host may well want exactly
        one of them.

        AUR on Arch (present in the AUR, absent from upstream Arch's repositories and from every
        derivative repository checked), plain `kubectl-cnpg` in nixpkgs, same version on both, and
        the AUR package's upstream URL is the operator's own repository -- the same project the
        nixpkgs homepage names. The command matches the package name on both platforms, which is
        worth stating only because no other entry in this file manages that.

        A kubectl PLUGIN, so it is found by being on PATH under this name and invoked as
        `kubectl cnpg ...`. Installing it without kubectl present leaves a working standalone
        binary and no plugin.
      '';
    };
  };
}
