# Proves the cluster module resolves what it claims and REFUSES what it claims to refuse, both
# directions, through the real renderer and the real app grammar.
#
# Both halves matter and neither is enough alone. A guard nobody has watched fire is a comment; a
# guard that fires on everything is a wall. So every case below is a complete, otherwise-valid tier
# with exactly one thing wrong, and the `control` case is the same shape with nothing wrong and MUST
# render -- without it, a typo in the shared base would make every other case "pass" for the wrong
# reason.
#
# Two refusals additionally have their MESSAGE asserted by content, because `tryEval` can only say
# THAT something was refused. For the ordering guard in particular, half of what is being checked is
# whether the refusal names both workloads and both numbers -- a refusal that does not is only half
# a guard, since the whole point is that a person has to move one of them deliberately.
{ pkgs, lib, nixidy, appsModule, addressingModule, clusterModule }:
let
  base = {
    nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
    nixidy.target.branch = "main";
    nixdb.clusterPlatform = {
      namespace = "example-dbs";
      project = "example-data";
    };
  };

  mkEnv = values: nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [ appsModule addressingModule clusterModule base values ];
  };

  renders = values:
    (builtins.tryEval (builtins.seq (mkEnv values).environmentPackage.drvPath true)).success;

  # The assertions themselves rather than the throw they eventually cause.
  failures = values:
    map (a: a.message)
      (lib.filter (a: !a.assertion) (mkEnv values).config.nixidy.assertions);

  ## ---------------------------------------------------------------------
  ## The floor: an empty tier renders nothing at all
  ## ---------------------------------------------------------------------

  emptyCfg = (mkEnv { }).config;

  ## ---------------------------------------------------------------------
  ## The control: a complete tier that must resolve
  ## ---------------------------------------------------------------------

  goodTier = {
    nixdb.operators.op = {
      operator = "cnpg";
      slot = 100;
      manifests = [ "apiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: op\n  namespace: example-dbs\n" ];
    };
    nixdb.instances = {
      pg-older = {
        engine = "postgres";
        version = "17";
        slot = 101;
        manifests = [ "apiVersion: postgresql.cnpg.io/v1\nkind: Cluster\nmetadata:\n  name: pg-older\n  namespace: example-dbs\nspec:\n  instances: 1\n" ];
      };
      pg-newer = {
        engine = "postgres";
        version = "18";
        slot = 102;
        manifests = [ "apiVersion: postgresql.cnpg.io/v1\nkind: Cluster\nmetadata:\n  name: pg-newer\n  namespace: example-dbs\nspec:\n  instances: 1\n" ];
      };
      sql = {
        engine = "mariadb";
        version = "11.8";
        slot = 107;
        createNamespace = true;
        state.data.hostPath = "/example/data/sql";
        credentials = { secret = "example-sql-root"; key = "rootPassword"; };
      };
    };
    nixdb.tools.browser = {
      tool = "whodb";
      version = "0.0.0";
      namespace = "example-browser";
      createNamespace = true;
      slot = 110;
      state.data.hostPath = "/example/data/browser";
      envFromSecrets = [ "example-browser-connections" ];
    };
  };

  goodCfg = (mkEnv goodTier).config;

  # One tier, two renderers, and the split is a property of the ENGINE rather than of the
  # declaration -- which is exactly what makes it worth pinning.
  sorted = lib.sort (a: b: a < b);

  ## ---------------------------------------------------------------------
  ## The failing direction
  ## ---------------------------------------------------------------------

  # Each case is `goodTier` with one thing changed. Written as whole tiers rather than as patches so
  # that a reader can see what is wrong without reconstructing it.
  mustFail = {
    # THE INTERLOCK. An instance of a managed engine with no operator is a custom resource nothing
    # reads: accepted by the API server, reported healthy by the syncing controller, and never a
    # database.
    managed-instance-with-no-operator =
      lib.recursiveUpdate goodTier { nixdb.operators.op.enable = false; };

    # A managed instance IS its custom resource. With none, the Application is empty.
    managed-instance-with-no-resource =
      lib.recursiveUpdate goodTier { nixdb.instances.pg-newer.manifests = lib.mkForce [ ]; };

    # The reverse: a self-managed engine is rendered in full by the grammar, so verbatim objects
    # here would be a second, untyped copy of what is already being rendered.
    self-managed-instance-passing-verbatim-objects =
      lib.recursiveUpdate goodTier { nixdb.instances.sql.manifests = [ "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n" ]; };

    # THE ORDERING GUARD: the operator above the instances it manages.
    operator-ordered-above-its-instances =
      lib.recursiveUpdate goodTier { nixdb.operators.op.slot = lib.mkForce 105; };

    # Every directory the engine writes must be backed by something. The multi-model engine writes
    # three, and an engine that comes up with two of them mounted looks healthy.
    engine-with-an-unbacked-directory =
      lib.recursiveUpdate goodTier {
        nixdb.instances.multimodel = {
          engine = "arcadedb";
          version = "26.5.1";
          slot = 108;
          state.data.hostPath = "/example/data/multimodel";
        };
      };

    state-with-no-backing =
      lib.recursiveUpdate goodTier { nixdb.instances.sql.state.data.hostPath = lib.mkForce null; };

    state-with-both-backings =
      lib.recursiveUpdate goodTier { nixdb.instances.sql.state.data.claim = "example-sql-data"; };

    # An engine that establishes its credentials some other way -- naming a Secret for it would
    # render nothing, which is worse than being refused.
    credentials-on-an-engine-that-reads-none =
      lib.recursiveUpdate goodTier {
        nixdb.instances.docs = {
          engine = "mongo";
          version = "8.0";
          slot = 106;
          state.data.hostPath = "/example/data/docs";
          credentials = { secret = "example-docs-root"; key = "password"; };
        };
      };

    two-workloads-on-one-slot =
      lib.recursiveUpdate goodTier { nixdb.tools.browser.slot = lib.mkForce 107; };

    two-workloads-creating-one-namespace =
      lib.recursiveUpdate goodTier { nixdb.tools.browser.namespace = lib.mkForce "example-dbs"; };

    # A Namespace created by a workload rendered below the grammar carries none of the grammar's
    # protection against being pruned -- and everything inside a database namespace is precisely
    # what must survive a manifest slip elsewhere in the tree.
    directly-rendered-workload-anchoring-a-namespace =
      lib.recursiveUpdate goodTier { nixdb.operators.op.createNamespace = true; };

    tool-passing-verbatim-objects =
      lib.recursiveUpdate goodTier { nixdb.tools.browser.manifests = [ "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n" ]; };
  };

  wronglyRendered = lib.attrNames (lib.filterAttrs (_: v: v) (lib.mapAttrs (_: renders) mustFail));

  # The ordering refusal, read as text. It has to name both workloads and both numbers, because
  # nothing here moves either of them and a person has to.
  orderingMessage =
    let msgs = failures mustFail.operator-ordered-above-its-instances; in
    if msgs == [ ] then "" else lib.head msgs;

  orderingMessageNames =
    lib.hasInfix "`op`" orderingMessage
    && (lib.hasInfix "`pg-older`" orderingMessage || lib.hasInfix "`pg-newer`" orderingMessage)
    && lib.hasInfix "105" orderingMessage
    && (lib.hasInfix "101" orderingMessage || lib.hasInfix "102" orderingMessage);

  # The unbacked-directory refusal has to say WHICH directories the engine writes and where, or the
  # reader has to go and find that out from somewhere else -- which is the whole failure this
  # catalogue exists to prevent.
  unbackedMessage =
    let msgs = lib.filter (m: lib.hasInfix "multimodel" m) (failures mustFail.engine-with-an-unbacked-directory); in
    if msgs == [ ] then "" else lib.head msgs;

  unbackedMessageNames =
    lib.hasInfix "/arcade_db" unbackedMessage
    && lib.hasInfix "/home/arcadedb/config" unbackedMessage
    && lib.hasInfix "/arcade_backup" unbackedMessage;

  results = {
    # ── The floor ─────────────────────────────────────────────────────────────────────────────
    "an empty tier defines no app in the grammar at all" =
      emptyCfg.nixk3s.apps == { };

    # The renderer defines applications of its own regardless of what is declared, so "adds
    # nothing" is asserted as a DIFFERENCE against an empty tier rather than against `{ }` -- which
    # also pins the other half in one expression: a declared tier contributes exactly its own
    # workloads to the render, by either route, and not one object more.
    "a declared tier's whole contribution to the render is exactly the workloads it declares" =
      sorted (lib.subtractLists (lib.attrNames emptyCfg.applications) (lib.attrNames goodCfg.applications))
      == sorted (goodCfg.nixdb.renderedByGrammar ++ goodCfg.nixdb.renderedDirectly);

    "an empty tier reports nothing rendered on either side, and claims no slots" =
      emptyCfg.nixdb.renderedByGrammar == [ ]
      && emptyCfg.nixdb.renderedDirectly == [ ]
      && emptyCfg.nixdb.slots == { };

    "an empty tier raises no assertion of its own -- an unused module must be silent" =
      lib.all (a: a.assertion) emptyCfg.nixidy.assertions;

    # ── The control ───────────────────────────────────────────────────────────────────────────
    "a complete tier renders" = renders goodTier;

    "self-managed engines and tooling go through the app grammar" =
      sorted goodCfg.nixdb.renderedByGrammar == [ "browser" "sql" ];

    "an operator's delivery and every managed instance go one level below it, countably" =
      sorted goodCfg.nixdb.renderedDirectly == [ "op" "pg-newer" "pg-older" ];

    "the two sides are disjoint and together account for every declared workload" =
      lib.intersectLists goodCfg.nixdb.renderedByGrammar goodCfg.nixdb.renderedDirectly == [ ]
      && lib.length (goodCfg.nixdb.renderedByGrammar ++ goodCfg.nixdb.renderedDirectly) == 5;

    "the grammar receives exactly the workloads it renders, with the engine's own knowledge filled in" =
      lib.attrNames goodCfg.nixk3s.apps == [ "browser" "sql" ]
      && goodCfg.nixk3s.apps.sql.image == "mariadb:11.8"
      && goodCfg.nixk3s.apps.sql.ports.mysql.number == 3306
      && goodCfg.nixk3s.apps.sql.state.data.mountPath == "/var/lib/mysql"
      && goodCfg.nixk3s.apps.sql.state.data.hostPath == "/example/data/sql";

    "the root credential arrives as a reference under the variable the ENGINE names, never as a value" =
      goodCfg.nixk3s.apps.sql.secrets.credentials.secret == "example-sql-root"
      && goodCfg.nixk3s.apps.sql.secrets.credentials.env.MARIADB_ROOT_PASSWORD == "rootPassword";

    "a probe is rendered on the port the catalogue calls primary, with the engine's own timing" =
      goodCfg.nixk3s.apps.sql.probes.readiness.port == "mysql"
      && goodCfg.nixk3s.apps.sql.probes.readiness.initialDelaySeconds == 15;

    # THE LADDER. Two majors of one engine, side by side, and nothing anywhere decides which is
    # current -- both are ordinary workloads with their own identity.
    "two rungs of one ladder are two independent workloads" =
      goodCfg.nixdb.slots.pg-older == 101
      && goodCfg.nixdb.slots.pg-newer == 102
      && goodCfg.applications.pg-older.namespace == goodCfg.applications.pg-newer.namespace;

    # The renderer normalizes both of these into the strings it will emit, which is why they are
    # compared as strings rather than as the booleans they are set with.
    "both rungs carry server-side apply and server-side diff -- a large custom resource cannot be applied client-side at all" =
      goodCfg.applications.pg-older.syncPolicy.syncOptions.serverSideApply == "ServerSideApply=true"
      && goodCfg.applications.pg-newer.compareOptions.serverSideDiff == "ServerSideDiff=true";

    "the slot report covers every workload that claims one, on both sides of the render split" =
      goodCfg.nixdb.slots == { op = 100; pg-older = 101; pg-newer = 102; sql = 107; browser = 110; };

    "the operator's chart coordinates are published WITHOUT a version -- a version here would be a second pin nothing keeps honest" =
      goodCfg.nixdb.operatorCharts.op == {
        repo = "https://cloudnative-pg.github.io/charts";
        name = "cloudnative-pg";
      };

    "the grammar-rendered workloads carry the declaring origin, so the band model governs their slots" =
      (mkEnv (lib.recursiveUpdate goodTier {
        nixdb.clusterPlatform.origin = "nixdb";
        nixk3s.addressing = {
          enable = true;
          bands.example-data = { base = 96; size = 32; };
          bindings.nixdb = "example-data";
        };
      })).config.nixk3s.apps.sql.origin == "nixdb";

    "and without that switch the grammar's apps name no origin at all -- those are the band model's terms, not this module's" =
      goodCfg.nixk3s.apps.sql.origin == null && goodCfg.nixk3s.apps.sql.slot == null;

    # ── The failing direction ─────────────────────────────────────────────────────────────────
    "every guard fires: nothing in the must-fail set renders" =
      wronglyRendered == [ ];

    "the ordering refusal names both workloads and both numbers, because a person has to move one" =
      orderingMessageNames;

    "the unbacked-directory refusal says which directories the engine writes, and where" =
      unbackedMessageNames;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then
  pkgs.writeText "nixdb-cluster-eval" ''
    control renders, the floor holds, and every guard fires:
    ${lib.concatMapStringsSep "\n" (n: "  refused: ${n}") (lib.attrNames mustFail)}
  ''
else
  throw ''
    nixdb: cluster-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
    ${lib.optionalString (wronglyRendered != [ ])
      "Declarations that rendered but had to be refused: ${lib.concatStringsSep ", " wronglyRendered}"}
  ''
