{
  description = "nixdb — the database tier, declared: engines and the operator that manages them as cluster workloads, plus the engine-specific clients a person installs to talk to them";

  # NO INPUTS FOR CONSUMERS, the same reasoning the sibling catalogues state for themselves: this
  # flake is options plus a catalogue, taking `pkgs`/`config`/`lib` from whichever evaluation
  # composes it, so a real host or a real cluster render never puts a second nixpkgs -- or a sibling
  # flake's whole input closure -- into its own closure. Everything below is used by `checks` alone;
  # nothing this flake EXPORTS reaches into any of it.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The renderer the cluster module defines into. A real input rather than a name in a comment:
    # without it there is no module system to evaluate the cluster side against, and `nix flake
    # check` would pass by checking nothing.
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # THE APP GRAMMAR THIS REPOSITORY CONSUMES. Also checks-only, and that is the point being
    # proven rather than a shortcut: a consumer imports the grammar itself, and this input exists so
    # `nix flake check` can render the cluster module through the REAL grammar and assert the
    # manifests that come out -- rather than asserting that a module which merely mentions
    # `nixk3s.apps` evaluates.
    nixk3s = {
      url = "github:julian-corbet/nixk3s-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixidy.follows = "nixidy";
    };
  };

  outputs = { self, nixpkgs, nixidy, nixk3s }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # The cluster plane. Composed into a nixidy environment ALONGSIDE the app grammar, which
      # declares the options this module defines into -- see modules/cluster.nix's own header.
      nixidyModules.nixdb = ./modules/cluster.nix;
      nixidyModules.default = ./modules/cluster.nix;

      # The host plane, for the engine-specific clients. Here the system is nix, so the backend
      # installs; on Arch there is nothing to install FROM, so the policy module IS that backend and
      # publishes package-name lists for the host's own reconciler. No third file exists to
      # re-export the second one -- see modules/clients.nix's own header.
      nixosModules.nixdb = ./modules/nixos.nix;
      nixosModules.default = ./modules/nixos.nix;

      systemManagerModules.nixdb = ./modules/clients.nix;
      systemManagerModules.default = ./modules/clients.nix;

      # Policy alone, for a consumer that wants the computed lists and will wire them itself, plus
      # the raw catalogues for inspection without re-reading the files.
      lib.clientsPolicy = ./modules/clients.nix;
      lib.cluster = ./modules/cluster.nix;
      lib.engines = import ./lib/engines.nix { };
      lib.clients = import ./lib/clients.nix { };

      # `nix flake check` evaluates none of the module outputs on its own, so a green check on this
      # repository without these three files would cover nothing but flake syntax.
      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # The cluster module, rendered through the real grammar and the real renderer, from the
          # placeholder values in examples/. Building the environment package forces the whole
          # manifest tree.
          env = nixidy.lib.mkEnv {
            inherit pkgs;
            modules = [
              nixk3s.nixidyModules.apps
              nixk3s.nixidyModules.addressing
              self.nixidyModules.nixdb
              ./examples/all/values.nix
            ];
          };
        in
        {
          # 1. The host catalogue, evaluated for real against `lib.evalModules`: which side of the
          # pacman/AUR split a name lands on, what a selection resolves to, and the catalogue's own
          # integrity -- including the cross-reference between the two catalogues.
          clients-eval = import ./checks/clients-eval.nix { inherit pkgs; };

          # 2. The cluster module's own resolution and every guard it makes, in BOTH directions:
          # an empty tier renders nothing at all, a declared tier resolves, and each refusal gets a
          # declaration that must be refused.
          cluster-eval = import ./checks/cluster-eval.nix {
            inherit pkgs lib nixidy;
            appsModule = nixk3s.nixidyModules.apps;
            addressingModule = nixk3s.nixidyModules.addressing;
            clusterModule = self.nixidyModules.nixdb;
          };

          # 3. The manifests the tier actually PRODUCED, parsed and asserted field by field. A
          # module that type-checks can still render an engine whose Service targets a port nothing
          # listens on, or one whose data directory is not mounted where the engine writes -- none
          # of that is an eval error and all of it is an outage.
          cluster-render = import ./checks/cluster-render.nix { inherit pkgs lib env; };
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
