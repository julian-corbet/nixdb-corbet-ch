#
# nixdb's cluster surface: declare what the database tier runs, and render it.
#
# ── THIS MODULE DOES NOT IMPLEMENT KUBERNETES, AND THAT IS THE WHOLE DESIGN ─────────────────────
#
# There is a sibling repository whose entire subject is the app grammar -- an app declares WHAT IT
# NEEDS (an image, ports, an exposure class, which existing claims or node paths hold its state,
# which existing Secrets it consumes) and that grammar renders the Argo CD Application, the
# Namespace, the Deployment and the Service. Everything this module can express in those terms is
# expressed in them: it DEFINES INTO `nixk3s.apps` and renders no Kubernetes object of its own.
#
# So this module is a translator, not a renderer. What it adds is the one thing the grammar cannot
# know: what a database IS. Which port the engine listens on, which directories it writes and what
# is lost when one of them is not mounted, how long a cold start takes before a probe means
# anything, whether a probe whose verdict is a RESTART can be answered at all, whether the software
# can be woken by a front that only sees HTTP, which environment variable carries the root
# credential, which client speaks to it, and which operator has to be present for its instances to
# be reconciled at all.
#
# ── WHERE EACH TERM LANDS, AND WHY IT IS NEVER A MATTER OF TASTE ───────────────────────────────
#
# Every option here is on one of two sides, and the test is the same one every time: would this be
# true of the software in ANYBODY's cluster?
#
#   KNOWLEDGE (../lib/engines.nix). The ports it listens on. The directories it writes. What a probe
#   ASKS and whether there is one to ask -- a liveness probe is only knowledge when the software has
#   an endpoint that tells a wedged process from a starting one, which is why most entries here have
#   none and that is deliberate. Whether it can be idled to zero at all, which is a fact about the
#   PROTOCOL somebody arrives on rather than about anybody's cluster.
#
#   VALUES (the options below). Which node path or claim backs a directory. Which Secret holds a
#   credential. Capacity, in `env`. A probe's BUDGET, because a budget is measured against hardware
#   and only the consumer has theirs. WHETHER an idleable workload is actually idled, and by which
#   front, because the same software is idled in one cluster and kept warm in another. And whether
#   an object with this workload's identity is ALREADY THERE (`adopt`), because that is the
#   receiving cluster's history rather than anything true of the software: the same engine at the
#   same version is taken over in the cluster that has been running it for a year and created fresh
#   in the one being built this week.
#
# The two halves are deliberately not interchangeable and the module refuses the crossings: a budget
# for a probe the catalogue does not define reaches no object and is an eval error, and asking for
# scale-to-zero on software the catalogue says cannot be woken is refused rather than rendered.
#
# IMPORT THE GRAMMAR ALONGSIDE THIS MODULE. `nixk3s.apps` is declared there, not here, and a render
# that composes this module without it fails with "the option `nixk3s.apps' does not exist". That
# is a hard requirement rather than an optional integration, and it is deliberately not softened:
# a version of this module that quietly rendered its own Deployments when the grammar was absent
# would be the second implementation this repository exists to not have.
#
# The grammar is NOT a flake input here, for the reason the sibling catalogues state for
# themselves: this repository is options plus a catalogue, taking `config`/`lib` from whichever
# evaluation composes it, so composing it can never add another flake's whole input closure to a
# consumer's. The input exists for `nix flake check` alone, which renders this module through the
# real grammar and asserts the manifests that come out.
#
# ── THE TWO THINGS THE GRAMMAR CANNOT EXPRESS, AND WHAT HAPPENS TO THEM ─────────────────────────
#
# Both are structural rather than a matter of taste, and both are named here so the boundary is
# visible instead of being discovered:
#
#   1. AN OPERATOR'S DELIVERY. An operator ships as its vendor's Helm chart -- a set of custom
#      resource definitions, RBAC, webhooks and a Deployment, versioned together by people who are
#      not us. The grammar renders a Deployment from an image, which is not that, and rebuilding
#      the chart's object set by hand here would be a second, permanently lagging copy of somebody
#      else's release.
#   2. A MANAGED INSTANCE. An instance of an operator-managed engine is a CUSTOM RESOURCE, not a
#      workload: the operator reads it and creates the pod, the Service, the credential and the
#      volume. The grammar always renders a Deployment, so it cannot express an Application that
#      renders none -- and the resource's own schema belongs to the operator's API version, not to
#      this repository's.
#
# Both therefore land on `applications.<name>` -- the RENDERER's own term, one level below the
# grammar -- with their object text taken as a value (`manifests`). That is the same move the
# grammar itself makes with its `raw` escape hatch, for the same reason it documents there: an
# abstraction people route around is worse than one visible hatch. `nixdb.renderedDirectly` lists
# every workload that took it, so the number is countable rather than a vague worry.
#
# SERVER-SIDE APPLY IS NOT OPTIONAL ON THOSE TWO, and the reason is a hard limit rather than a
# preference: an operator's custom resource definitions are large enough that a client-side apply
# overruns the 262144-byte annotation Kubernetes keeps the last-applied state in, and the apply
# simply fails. Server-side diff comes with it, because comparing a client-side reconstruction of a
# large resource against what the API server actually holds produces permanent phantom drift.
#
# ── AN OPERATOR SITS BELOW THE INSTANCES IT MANAGES ────────────────────────────────────────────
#
# Where a fleet maps its workloads onto an ordered identity space, an operator takes the position
# immediately below the group it manages and its instances follow above it. This module REFUSES the
# inverted ordering at eval, naming both workloads and both numbers.
#
# It is a guard over a relationship, never an allocator: no number is assigned here, none is moved,
# and none appears anywhere in this repository. Which positions exist is the shape of somebody's
# fleet; that the operator comes first is a property of the subsystem and is the same everywhere.
#
# THE BAND THOSE NUMBERS COME FROM IS SOMEBODY ELSE'S QUESTION. The sibling band model governs
# WHICH RANGE a declaring repository's workloads may take a slot from; this module governs the
# ORDER of the tier's own workloads within whatever range that is. Two different questions, each
# answered where it belongs, and `nixdb.clusterPlatform.origin` is the one switch that hands the
# numbers to the band model when it is part of the same render.
#
# ── ONE ENGINE IS NOT ONE VERSION ──────────────────────────────────────────────────────────────
#
# `version` is required on every declaration and has no default anywhere in this repository. A tier
# routinely runs several majors of one engine side by side, permanently, and the catalogue holds
# KINDS of engine rather than copies of one. Declare one instance per rung; they may share a
# namespace, they will listen on the same port in different Services, and nothing here has an
# opinion about which of them is "current".
#
# ONE NAMESPACE. Everything declared here lives under `nixdb`, like every repo in this family.
{ config, lib, ... }:
let
  cfg = config.nixdb;
  platform = cfg.clusterPlatform;

  engines = import ../lib/engines.nix { };

  enabledOf = attrs: lib.filterAttrs (_: w: w.enable) attrs;

  operators = enabledOf cfg.operators;
  instances = enabledOf cfg.instances;
  tools = enabledOf cfg.tools;

  catOperator = w: engines.operators.${w.operator};
  catEngine = w: engines.engines.${w.engine};
  catTool = w: engines.tooling.${w.tool};

  # Every declared workload, tagged with its kind and its catalogue entry, in one list. The
  # assertions and the reports are written against THIS rather than against three separate tables,
  # because almost every guard here is about the tier as a whole: two workloads on one number, two
  # workloads creating one namespace, an operator ordered above its instances.
  allWorkloads =
    lib.mapAttrsToList (name: w: { inherit name w; kind = "operator"; entry = catOperator w; }) operators
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "instance"; entry = catEngine w; }) instances
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "tool"; entry = catTool w; }) tools;

  # An instance is MANAGED when its engine's instances are custom resources rather than containers.
  # The one fork in this module's behaviour, and it is read from the catalogue rather than declared
  # by the consumer: whether an engine has an operator between the declaration and the process is a
  # fact about the engine.
  isManaged = w: (catEngine w).managed;

  # Which workloads the grammar renders, and which ones go one level below it. Every branch in this
  # module is one of these two, so they are computed once and named.
  byGrammar = lib.filter
    (x: (x.kind == "tool") || (x.kind == "instance" && !(isManaged x.w)))
    allWorkloads;

  directly = lib.filter
    (x: (x.kind == "operator" && x.w.manifests != [ ]) || (x.kind == "instance" && isManaged x.w))
    allWorkloads;

  ## ---------------------------------------------------------------------
  ## Translation into the app grammar
  ## ---------------------------------------------------------------------

  # `image` is the catalogue's repository plus the declaration's version, unless the declaration
  # names a whole reference itself -- which is what pinning by digest looks like, and what the
  # grammar warns about the absence of.
  imageOf = entry: w:
    if w.image != null then w.image else "${entry.image}:${w.version}";

  portsOf = entry: lib.mapAttrs (_: number: { inherit number; }) entry.ports;

  # The knowledge/value split, in one function: WHERE inside the container comes from the
  # catalogue, WHAT BACKS IT comes from the declaration, and neither side can supply the other's
  # half.
  stateOf = entry: w:
    lib.mapAttrs
      (key: backing: {
        mountPath = entry.state.${key};
        inherit (backing) claim hostPath hostPathType readOnly;
      })
      w.state;

  # Two shapes of secret consumption, and no third: one named key carrying the engine's root
  # credential, and whole Secrets loaded wholesale for anything whose keys change without the
  # declaration changing. Nothing here can carry a secret's CONTENT, which is what makes a
  # declaration written against this module safe to publish.
  secretsOf = entry: w:
    lib.optionalAttrs ((w.credentials or null) != null && (entry.rootSecretEnv or null) != null)
      {
        credentials = {
          secret = w.credentials.secret;
          env.${entry.rootSecretEnv} = w.credentials.key;
        };
      }
    // lib.listToAttrs (map (s: lib.nameValuePair s { secret = s; envFrom = true; }) w.envFromSecrets);

  # THE KNOWLEDGE/VALUE SPLIT, ON A PROBE. WHAT is asked -- which port, which path, whether there
  # is a liveness probe at all -- is the catalogue's, because it is a property of the software. The
  # TIMING is the catalogue's MEASURED DEFAULT and the declaration's to override, because a budget
  # is measured against hardware and only the consumer knows theirs.
  #
  # The override can never reach `port` or `path`, and that is the whole line: a cluster that wants
  # a different budget has different disks, while a cluster that wants a different endpoint has
  # discovered something about the software and belongs in the catalogue.
  budgetedProbe = shape: over:
    shape // lib.filterAttrs (_: v: v != null) {
      inherit (over) initialDelaySeconds periodSeconds timeoutSeconds failureThreshold;
    };

  probeOf = entry: shape: over:
    { port = entry.primaryPort; } // budgetedProbe shape over;

  probesOf = entry: w:
    lib.optionalAttrs (entry.readiness != null)
      { readiness = probeOf entry entry.readiness w.probeBudget.readiness; }
    // lib.optionalAttrs (entry.liveness != null)
      { liveness = probeOf entry entry.liveness w.probeBudget.liveness; };

  # Which probes this software actually has, for the guard that refuses a budget nothing would
  # spend. Read off the catalogue, so it is right for all three kinds of workload at once --
  # an operator and a managed instance have none of either.
  probeShapes = entry: {
    readiness = entry.readiness != null;
    liveness = entry.liveness != null;
  };

  budgetIsSet = over: lib.any (v: v != null) (lib.attrValues over);

  # Handed to the band model only when the consumer says it is part of the render: `origin` and
  # `slot` are ITS terms, and defining them into a render that does not declare them is an eval
  # error rather than a graceful no-op.
  addressingOf = w:
    lib.optionalAttrs (platform.origin != null) {
      origin = platform.origin;
      inherit (w) slot;
    };

  mkGrammarApp = x:
    let inherit (x) entry w; in
    {
      inherit (w) namespace createNamespace project exposure;
      image = imageOf entry w;
      ports = portsOf entry;
      state = stateOf entry w;
      secrets = secretsOf entry w;
      env = entry.env // w.env;
      args = entry.args ++ w.args;
      probes = probesOf entry w;
      inherit (w) scaling;
      # Straight through, because the term is the grammar's and the ANSWER is the consumer's
      # cluster's history. Nothing here can derive it: no catalogue entry knows what is already
      # running in somebody's cluster.
      inherit (w) adopt;
    }
    // lib.optionalAttrs (w.wake != null) { inherit (w) wake; }
    // addressingOf w;

  ## ---------------------------------------------------------------------
  ## The two objects the grammar cannot express
  ## ---------------------------------------------------------------------

  mkDirectApp = x:
    let inherit (x) w; in
    {
      inherit (w) namespace project;
      # Never here: the Namespace this renderer creates carries no protection against being read
      # as no-longer-desired, and the anchor for a shared namespace belongs to a workload the
      # grammar renders (which stamps that protection) or to the tenancy layer. Asserted below.
      createNamespace = false;
      yamls = w.manifests;
      syncPolicy.syncOptions.serverSideApply = true;
      compareOptions.serverSideDiff = true;
    };

  ## ---------------------------------------------------------------------
  ## Derived facts the guards are written against
  ## ---------------------------------------------------------------------

  slotClaims = lib.filter (x: x.w.slot != null) allWorkloads;
  claimantsOf = slot: map (x: x.name) (lib.filter (x: x.w.slot == slot) slotClaims);
  duplicatedSlots =
    lib.filter (slot: lib.length (claimantsOf slot) > 1)
      (lib.unique (map (x: x.w.slot) slotClaims));

  creatorsOf = ns:
    map (x: x.name) (lib.filter (x: x.w.createNamespace && x.w.namespace == ns) allWorkloads);
  createdNamespaces = lib.unique
    (map (x: x.w.namespace) (lib.filter (x: x.w.createNamespace) allWorkloads));

  # The operators actually declared, by catalogue key rather than by declaration name -- what a
  # managed instance needs is "an operator of this kind is present", not one with a particular
  # name.
  declaredOperatorKeys = lib.unique (lib.mapAttrsToList (_: w: w.operator) operators);

  # DECLARED IS NOT DELIVERED, and the difference is load-bearing for the interlock below.
  #
  # An operator declared with `manifests = [ ]` renders nothing here -- that is the supported shape
  # for a chart deployed by an application of the consumer's own. But it means the interlock could
  # be satisfied by a declaration that ships no operator at all: the consumer drops the application
  # that actually delivers the chart, this module still evaluates green, and the managed instances
  # become custom resources with nothing to reconcile them. Exactly the failure the interlock exists
  # to prevent, reached through the one door it did not watch.
  #
  # `manifests == [ ]` is precisely the case where THIS module defines no `applications.<name>`, so
  # the attribute existing means something else in the same environment defines it. That makes the
  # check exact rather than heuristic: no ownership guessing, no definition-site introspection.
  deliveredElsewhere = name: config.applications ? ${name};

  undeliveredOperators = lib.filter
    (name: operators.${name}.manifests == [ ] && !(deliveredElsewhere name))
    (lib.attrNames operators);

  operatorsManaging = engineKey:
    lib.filter (x: lib.elem engineKey x.entry.manages)
      (lib.filter (x: x.kind == "operator") allWorkloads);

  managedInstancesOf = operatorEntry:
    lib.filter
      (x: x.kind == "instance" && isManaged x.w && lib.elem x.w.engine operatorEntry.manages)
      allWorkloads;

  ## ---------------------------------------------------------------------
  ## Assertions
  ## ---------------------------------------------------------------------

  # Stated as a total function of the workload. The module system keeps only the FAILING assertions
  # and formats those messages, so a message is evaluated at exactly the moment its own assertion
  # has failed -- and one that throws on a partial declaration takes the whole evaluation down
  # instead of reporting anything. That same filtering means a value mentioned ONLY in a message is
  # never forced, and so never type-checked: whatever an assertion wants checked has to be in its
  # `assertion` expression. See nixwatch's study `an-option-nothing-renders-is-never-checked`.
  showSlot = w: if w.slot == null then "(none)" else toString w.slot;

  instanceAssertions = lib.concatMap
    (x:
      let inherit (x) name w entry; in
      [
        {
          # The interlock. An instance of a managed engine is a custom resource and nothing else:
          # with no operator to read it, the object is accepted by the API server, reported healthy
          # by the syncing controller, and no database is ever created.
          assertion = !(isManaged w) || lib.elem entry.operator declaredOperatorKeys;
          message =
            "nixdb: instance `${name}` runs engine `${w.engine}`, whose instances are custom resources "
            + "reconciled by the `${toString entry.operator}` operator -- and no such operator is declared. "
            + "The resource would be accepted and reported healthy, and no database would ever exist. "
            + "Declare it in `nixdb.operators`, or use an engine that runs as its own container.";
        }
        {
          assertion = !(isManaged w) || w.manifests != [ ];
          message =
            "nixdb: instance `${name}` runs a managed engine, so it IS a custom resource -- and `manifests` "
            + "is empty, which renders an Application with nothing in it. The resource's schema belongs to "
            + "the operator's own API version rather than to this repository, so its text is taken as a "
            + "value: put the object in `nixdb.instances.${name}.manifests`.";
        }
        {
          assertion = isManaged w || w.manifests == [ ];
          message =
            "nixdb: instance `${name}` runs a self-managed engine, which the app grammar renders in full -- "
            + "so `manifests` here would be a second, untyped copy of objects that are already being "
            + "rendered. For an extra object the grammar has no term for, use ITS escape hatch "
            + "(`nixk3s.apps.${name}.raw`), which is scanned, warned about and counted.";
        }
        {
          # Every directory the engine writes has to be backed by something. An engine that comes
          # up with an unmounted config or backup directory looks healthy and quietly loses that
          # directory on every restart.
          assertion = isManaged w || lib.attrNames w.state == lib.attrNames entry.state;
          message =
            "nixdb: instance `${name}` (engine `${w.engine}`) must back every directory the engine writes, "
            + "and backs "
            + (if w.state == { } then "none" else lib.concatMapStringsSep ", " (k: "`${k}`") (lib.attrNames w.state))
            + ". The engine writes: "
            + lib.concatStringsSep ", " (lib.mapAttrsToList (k: p: "`${k}` at ${p}") entry.state)
            + ". An unbacked one is not an error at runtime -- the engine starts, uses the container's own "
            + "filesystem, and loses it at the next restart.";
        }
        {
          assertion = lib.all
            (backing: (backing.claim == null) != (backing.hostPath == null))
            (lib.attrValues w.state);
          message =
            "nixdb: instance `${name}` backs a directory with neither or both of `claim` and `hostPath`. "
            + "Storage needs exactly one backing: an existing claim by name, or a path on the node.";
        }
        {
          assertion = (entry.rootSecretEnv or null) != null || w.credentials == null;
          message =
            "nixdb: instance `${name}` names `credentials`, but engine `${w.engine}` reads no root credential "
            + "from its environment -- see that entry's own note for how its credentials are actually "
            + "established. The reference would render nothing, which is worse than being refused.";
        }
      ])
    (lib.filter (x: x.kind == "instance") allWorkloads);

  toolAssertions = lib.concatMap
    (x:
      let inherit (x) name w entry; in
      [
        {
          assertion = lib.attrNames w.state == lib.attrNames entry.state;
          message =
            "nixdb: tool `${name}` must back every directory it writes, and backs "
            + (if w.state == { } then "none" else lib.concatMapStringsSep ", " (k: "`${k}`") (lib.attrNames w.state))
            + ". It writes: "
            + lib.concatStringsSep ", " (lib.mapAttrsToList (k: p: "`${k}` at ${p}") entry.state)
            + ".";
        }
        {
          assertion = lib.all
            (backing: (backing.claim == null) != (backing.hostPath == null))
            (lib.attrValues w.state);
          message =
            "nixdb: tool `${name}` backs a directory with neither or both of `claim` and `hostPath`. "
            + "Storage needs exactly one backing.";
        }
        {
          assertion = w.manifests == [ ];
          message =
            "nixdb: tool `${name}` is rendered in full by the app grammar, so `manifests` here would render "
            + "nothing at all. For an extra object beside it, use the grammar's own escape hatch "
            + "(`nixk3s.apps.${name}.raw`), which is warned about and counted.";
        }
      ])
    (lib.filter (x: x.kind == "tool") allWorkloads);

  # THE GUARDS OVER THE TWO TERMS WHOSE HALVES LIVE ON OPPOSITE SIDES OF THE SPLIT -- whether this
  # workload may be idled, and what a probe budget is allowed to tune. Written against every
  # workload rather than per kind, because both read the CATALOGUE entry and every kind has one:
  # an operator's answer to "may this be idled" is as real as an engine's.
  classAssertions = lib.concatMap
    (x:
      let
        inherit (x) name w entry;
        shapes = probeShapes entry;
      in
      [
        {
          # A wake front holds an HTTP request and replays it. Nothing holds a connection on a wire
          # protocol, so a sleeping engine is not woken by the client that wanted it -- it refuses
          # the connection, instantly, and nothing anywhere records that anybody tried.
          assertion = w.scaling != "scale-to-zero" || entry.idleable;
          message =
            "nixdb: ${x.kind} `${name}` asks to be idled to zero, and the software it runs cannot be woken. "
            + "A wake front sees a request only over HTTP; this is reached over its own wire protocol, or "
            + "over no ingress at all, so a client arriving while the pod is down gets a refused connection "
            + "and nothing starts anything. The pod would go to sleep once and stay there. Leave `scaling` at "
            + "`always`, and idle whatever fronts it instead.";
        }
        {
          assertion = !(budgetIsSet w.probeBudget.readiness) || shapes.readiness;
          message =
            "nixdb: ${x.kind} `${name}` sets a readiness-probe budget, and this software has no readiness "
            + "probe in the catalogue -- so every number in that budget would reach no object at all. A "
            + "budget tunes a probe's TIMING; whether there is a probe to time, and what it asks, is a "
            + "property of the software and lives in the catalogue.";
        }
        {
          assertion = !(budgetIsSet w.probeBudget.liveness) || shapes.liveness;
          message =
            "nixdb: ${x.kind} `${name}` sets a liveness-probe budget, and this software has no liveness probe "
            + "in the catalogue -- which for most of what this repository catalogues is deliberate rather "
            + "than missing: a probe whose verdict is a RESTART needs an endpoint that tells a wedged "
            + "process from a slow-starting one, and an engine mid-recovery answers exactly like a dead one. "
            + "The budget would reach no object. If this software really does have such an endpoint, that is "
            + "a catalogue entry, not a number here.";
        }
      ])
    allWorkloads;

  # THE ORDERING GUARD. One pair at a time, so the refusal names both workloads and both numbers
  # rather than reporting that something, somewhere, is out of order.
  orderingAssertions = lib.concatMap
    (op: map
      (inst: {
        assertion = op.w.slot == null || inst.w.slot == null || op.w.slot < inst.w.slot;
        message =
          "nixdb: operator `${op.name}` holds slot ${showSlot op.w} and the instance it manages, "
          + "`${inst.name}`, holds ${showSlot inst.w}. An operator takes the position immediately BELOW "
          + "the instances it manages: an operator and its instances are one subsystem, and the ordering "
          + "is read by people, for whom a subsystem reads correctly only when the thing that reconciles "
          + "comes before the things it reconciles. Nothing here will move either number for you -- a slot "
          + "is a live identity in every space a fleet maps it into. Move them deliberately.";
      })
      (managedInstancesOf op.entry))
    (lib.filter (x: x.kind == "operator") allWorkloads);

  tierAssertions =
    map
      (name: {
        assertion = false;
        message =
          "nixdb: operator `${name}` is declared with no `manifests`, and nothing in this environment "
          + "delivers it either -- there is no `applications.${name}`. An empty `manifests` means "
          + "\"its chart is deployed by an application of my own\", so this declaration currently "
          + "promises an operator that does not exist. Every managed instance depending on it would "
          + "render a custom resource the API server accepts and reports healthy while no database is "
          + "ever created. Deliver the chart from an application of your own, or put its rendered "
          + "objects in `manifests` here.";
      })
      undeliveredOperators
    ++ map
      (slot: {
        assertion = false;
        message =
          "nixdb: slot ${toString slot} is claimed by more than one workload in this tier: "
          + lib.concatMapStringsSep ", " (n: "`${n}`") (claimantsOf slot)
          + ". A slot is one identity in every address space the fleet maps it into, so two claimants is a "
          + "collision in all of them at once.";
      })
      duplicatedSlots
    ++ map
      (ns: {
        assertion = lib.length (creatorsOf ns) == 1;
        message =
          "nixdb: namespace `${ns}` is created by more than one workload in this tier: "
          + lib.concatMapStringsSep ", " (n: "`${n}`") (creatorsOf ns)
          + ". Two Applications owning one Namespace fight over it. Let exactly one anchor it, or anchor it "
          + "in the tenancy layer and set `createNamespace = false` on all of them.";
      })
      createdNamespaces
    ++ map
      (x: {
        # Lesson paid for elsewhere and encoded here: a Namespace created by an Application that
        # this module renders one level below the grammar carries none of the grammar's protection
        # against being read as no-longer-desired -- and everything inside a database namespace is
        # exactly what must not be cascade-deleted.
        assertion = !x.w.createNamespace;
        message =
          "nixdb: workload `${x.name}` is rendered below the app grammar (it delivers whole objects rather "
          + "than a container), and `createNamespace` here would produce a Namespace with no protection "
          + "against being pruned -- which for a namespace holding databases takes the databases with it. "
          + "Let a grammar-rendered workload anchor the namespace, or anchor it in the tenancy layer.";
      })
      directly;

  ## ---------------------------------------------------------------------
  ## Warnings
  ## ---------------------------------------------------------------------

  warnings =
    map
      (x: {
        when = x.w.manifests == [ ];
        message =
          "nixdb: operator `${x.name}` is declared but delivers nothing here -- `manifests` is empty, so no "
          + "objects are rendered for it. That is correct when its chart is deployed by something else in "
          + "the same cluster, and the declaration still buys the interlocks (an instance of a managed "
          + "engine now knows its operator is present, and the ordering against its instances is checked). "
          + "If it was meant to be delivered from here, it is not.";
      })
      (lib.filter (x: x.kind == "operator") allWorkloads)
    ++ map
      (x: {
        when = x.w.exposure != "internal";
        message =
          "nixdb: workload `${x.name}` declares exposure `${x.w.exposure}`, which is a term of the app "
          + "grammar -- and this workload is rendered below the grammar, so the class reaches no object. "
          + "Whatever fronts it is selecting on something else.";
      })
      directly
    ++ map
      (x: {
        when = x.w.wake != null;
        message =
          "nixdb: workload `${x.name}` names the `${toString x.w.wake}` wake front, which is a term of the "
          + "app grammar -- and this workload is rendered below the grammar, so the name reaches no object. "
          + "Nothing will wake it, and nothing is asleep either.";
      })
      directly
    ++ map
      (x: {
        when = x.w.slot != null && platform.origin == null;
        message =
          "nixdb: workload `${x.name}` claims slot ${showSlot x.w}, and `nixdb.clusterPlatform.origin` is "
          + "unset -- so the number is checked for order and for collisions inside this tier, and by nothing "
          + "for which RANGE it may come from. Set the origin when the band model is part of the same "
          + "render.";
      })
      allWorkloads;

  ## ---------------------------------------------------------------------
  ## Option shapes shared by all three kinds of workload
  ## ---------------------------------------------------------------------

  backingType = lib.types.submodule {
    options = {
      claim = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          NAME of an existing PersistentVolumeClaim backing this directory. A name, never a path.
          Nothing here creates the claim: it outlives every version of the engine that mounts it,
          so its existence is not the engine's to declare.
        '';
      };

      hostPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path on the NODE backing this directory instead of a claim, and in practice the more
          common answer for a database: the directory is usually a tuned filesystem somebody
          curates deliberately.

          IT PINS THE WORKLOAD TO A NODE, because the path only exists on one. The VALUE is a fleet
          fact and belongs to the consumer that passes it in -- no path appears anywhere in this
          repository.
        '';
      };

      hostPathType = lib.mkOption {
        type = lib.types.enum [ "Directory" "DirectoryOrCreate" ];
        default = "Directory";
        description = ''
          Whether a missing node path is an error or is created empty. `Directory` (the default)
          refuses to start, which is the right answer for a database's own data directory: an
          engine that finds an empty directory INITIALISES A NEW ONE, and a fresh empty database
          reports itself healthy. `DirectoryOrCreate` is for a directory the engine merely writes
          into (a backup or config directory that starts out empty), where a missing path is
          genuinely a first run rather than a mount that failed.
        '';
      };

      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Mount read-only. Almost never right for a database: engines write to directories that
          look read-only from outside, including the one that holds server configuration.
        '';
      };
    };
  };

  # A probe's TIMING and nothing else. There is deliberately no `port` and no `path` here: those
  # are what the probe ASKS, which is a property of the software and comes from the catalogue. Each
  # field is null by default and null means "keep what was measured", so an override is exactly as
  # wide as what the consumer actually knows differently.
  probeBudgetType = lib.types.submodule {
    options = {
      initialDelaySeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = ''
          Delay before the first probe. Raise it when this hardware takes longer to reach the point
          where the catalogue's answer would even be meaningful -- probing sooner spends the failure
          budget on a certainty.
        '';
      };

      periodSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Interval between probes.";
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          How long one probe may take before it counts as failed. The field a busy or contended node
          usually needs, and the one whose absence looks like a flapping workload rather than a
          slow one.
        '';
      };

      failureThreshold = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          Consecutive failures before the verdict is acted on. Together with `periodSeconds` this is
          how long a slow start is tolerated, and on a readiness probe it is the number that decides
          whether a cold start is a wake or a restart loop.
        '';
      };
    };
  };

  commonOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render this workload. Declaring the attribute is declaring the workload, so this
        defaults to true; set false to park a declaration without rendering it.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = platform.namespace;
      defaultText = lib.literalExpression "config.nixdb.clusterPlatform.namespace";
      description = "Namespace this workload lands in.";
    };

    createNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this workload anchors its namespace. Defaults to false: a namespace holding
        databases outlives every workload in it, and exactly one thing may own it. Two workloads
        creating one namespace fails eval.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = platform.project;
      defaultText = lib.literalExpression "config.nixdb.clusterPlatform.project";
      description = "Delivery project this workload's Application belongs to.";
    };

    slot = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = ''
        THE POSITION this workload holds in the fleet's ordered identity space. Not an address --
        the layers underneath map it into however many address spaces the fleet keeps, which is
        exactly why nothing here moves one.

        The VALUE is a fleet fact and belongs to the consumer that passes it in. What this module
        does with it is refuse two workloads on one number, and refuse an operator ordered above
        the instances it manages. Which RANGE the numbers may come from is a different question,
        answered by the band model -- see `nixdb.clusterPlatform.origin`.
      '';
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" "public" ];
      default = "internal";
      description = ''
        WHO can reach this workload, as a class and never an address. `internal` is the default and
        is right for every engine: a database is reached by the workloads that depend on it, from
        inside the cluster.

        A term of the app grammar, so it reaches an object only on the workloads the grammar
        renders. On the two kinds it does not (an operator's delivery, a managed instance) a
        non-default value warns rather than pretending to do something.
      '';
    };

    scaling = lib.mkOption {
      type = lib.types.enum [ "always" "scale-to-zero" ];
      default = "always";
      description = ''
        WHETHER this deployment idles the workload to zero and wakes it on demand. `always` is the
        default and is the only answer for an engine.

        The DECISION is a value and belongs here -- a visualiser nobody opens most days and the same
        visualiser on a workstation somebody keeps open are the same software with different answers.
        Whether the decision is available at all is knowledge and comes from the catalogue
        (`idleable`): software reached over its own wire protocol can never be woken by an HTTP
        front, so `scale-to-zero` on an engine is refused rather than rendered.

        A term of the app grammar, so like `exposure` it reaches an object only on the workloads
        that grammar renders.
      '';
    };

    wake = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "keda" "sablier" ]);
      default = null;
      description = ''
        WHICH wake front brings this workload up, on the deployments that idle it. A value, and one
        of the plainest: it names a piece of software running in somebody's cluster, and the same
        workload is fronted by whichever one that cluster already runs.

        `null` (the default) lets the app grammar pick. Meaningless without
        `scaling = "scale-to-zero"`, and the grammar refuses it there rather than rendering a label
        about a front that will never exist.
      '';
    };

    adopt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        WHETHER an object with this workload's identity is ALREADY IN the cluster this render lands
        on -- applied by an addon, by hand, or by the manifest tree this declaration replaces. It
        renders the Application with server-side apply and server-side diff, so the delivery tool
        compares against what the API server actually holds rather than against a client-side
        reconstruction of it.

        A VALUE, and one of the plainest ones here: whether an object already exists is the
        receiving cluster's HISTORY, never a property of the software. The same engine at the same
        version is taken over in one cluster and created fresh in another, and those two
        declarations differ here and nowhere else -- which is exactly why no catalogue entry could
        carry it.

        IT MATTERS MOST ON PRECISELY WHAT THIS REPOSITORY DECLARES. A rendered spec is never
        byte-identical to the YAML it replaces -- labels differ, fields this grammar sets appear,
        fields it does not set disappear -- and durable `state` forces `Recreate`, which stops the
        old pod before starting the new one. So the diff a client-side apply invents is not a
        rollout nobody notices here, it is a database going down. Server-side apply and diff shrink
        that diff to what genuinely changed, which is what makes an in-place adoption possible at
        all; it does not make it zero. Render it, diff it against what is live, and decide
        knowingly.

        A term of the app grammar, so it reaches an object only on the workloads the grammar
        renders. On the two kinds it does not -- an operator's delivery, a managed instance --
        server-side apply is UNCONDITIONAL and this term is neither read nor needed: a custom
        resource definition overruns the 262144-byte annotation a client-side apply keeps its last
        state in, so there is no version of those two that is applied any other way. Leaving this
        at its default there does not turn that off.
      '';
    };

    probeBudget = lib.mkOption {
      type = lib.types.submodule {
        options = {
          readiness = lib.mkOption {
            type = probeBudgetType;
            default = { };
            description = "Timing override for the readiness probe the catalogue defines.";
          };
          liveness = lib.mkOption {
            type = probeBudgetType;
            default = { };
            description = "Timing override for the liveness probe the catalogue defines.";
          };
        };
      };
      default = { };
      description = ''
        THE TIMING of this workload's probes, where this cluster's hardware differs from what the
        catalogue measured. Only the timing: what a probe asks -- which port, which path, whether
        there is a liveness probe at all -- is a property of the software and is not overridable
        from here at all.

        Every field defaults to null, meaning "keep the measured value", so an override says exactly
        what the consumer knows differently and nothing more. Setting one for a probe this software
        does not have is refused: the number would reach no object, which is worse than being told.
      '';
    };

    state = lib.mkOption {
      type = lib.types.attrsOf backingType;
      default = { };
      description = ''
        What BACKS each directory this software writes, keyed by the catalogue's own name for it.
        Where each one lands inside the container is knowledge and comes from the catalogue; what
        holds it is a value and comes from here.

        Every directory the catalogue names must appear -- an engine whose configuration or backup
        directory is unbacked starts, looks healthy, and loses it at the next restart.
      '';
    };

    envFromSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        NAMES of existing Secrets loaded wholesale into the environment. For software whose set of
        environment keys changes without its declaration changing -- a browser's list of database
        connections, for instance. Nothing here carries a secret's content; a rendered manifest
        tree is committed to git.
      '';
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra plain environment, merged OVER whatever the catalogue supplies for this software.
        Plain is the operative word: a credential belongs in a Secret, and an address belongs to
        whatever allocates addresses -- the app grammar scans these values and refuses an address
        literal.

        This is where capacity goes: heap sizes, cache sizes, worker counts. The catalogue supplies
        what the software needs in order to be CORRECT and never what it needs in order to be the
        right size, because only the consumer knows the hardware.
      '';
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra entrypoint arguments, appended to whatever the catalogue supplies.";
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Whole image reference, replacing the catalogue repository plus `version`. Set it to PIN BY
        DIGEST (`repository:tag@sha256:...`), which is the only way two syncs of an identical
        rendered tree cannot run different code -- the grammar warns while it is unpinned.

        `null` (the default) builds the reference from the catalogue's repository and this
        workload's `version`.
      '';
    };

    manifests = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Whole objects, as YAML documents, delivered under this workload's Application.

        This is where the two things the app grammar cannot express arrive: an operator's own chart
        output, and the custom resource that IS a managed instance. In both cases the object's
        schema belongs to somebody else's release rather than to this repository, so its text is a
        value -- exactly like a node path.

        Refused on a workload the grammar renders in full. For one extra object beside a rendered
        engine, use the grammar's own escape hatch, which is scanned, warned about and counted.
      '';
    };

  };
in
{
  options.nixdb.clusterPlatform = {
    namespace = lib.mkOption {
      type = lib.types.str;
      description = ''
        The namespace this tier's workloads land in unless one says otherwise. NO DEFAULT, and
        evaluation fails naming this option the moment any workload is declared: what a cluster
        calls its database namespace is a value, and a default here would be this repository
        deciding it.

        One namespace for the whole tier is the usual shape and the one this option is written for
        -- the engines share a lifecycle, a storage location and an audience -- but nothing
        enforces it, and any workload may name its own.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Delivery project every workload in this tier lands in unless it says otherwise.

        Defaults to `default` -- the delivery tool's own built-in project, which permits every
        destination and is therefore the answer that cannot break a render. It is not the answer to
        leave in place: name a project of your own so the tier is governed like everything else.
      '';
    };

    origin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "nixdb";
      description = ''
        The declaring-origin name to stamp on the workloads the app grammar renders, handing their
        slots to the BAND MODEL -- which governs which range of the identity space a declaring
        repository's workloads may take a number from.

        `null` by default because `origin` and `slot` are that model's terms: defining them into a
        render that does not include it fails with "the option does not exist". Set this only when
        it is part of the same render, and set it to the name that model binds a band for.

        This module's own ordering guard runs either way -- an operator above the instances it
        manages is refused whether or not anything is governing the range.
      '';
    };
  };

  options.nixdb.operators = lib.mkOption {
    default = { };
    description = ''
      Operators present in this cluster, keyed by a name of your choosing. An operator is software
      that reconciles instances of an engine: the instances are custom resources, and the operator
      is what turns them into running databases.

      A declaration here does two things. It DELIVERS the operator, when `manifests` carries its
      chart output -- and it GOVERNS, always: an instance of a managed engine now knows its
      operator is present, and the ordering between the operator and its instances is checked.
      Declaring one without `manifests` is the correct shape when its chart is deployed by
      something else, and it warns so that the absence is never silent.
    '';
    example = lib.literalExpression ''
      {
        example-operator = {
          operator = "cnpg";
          slot = 33;          # a value the consumer supplies; instances follow above it
          manifests = [ (builtins.readFile ./rendered-operator-chart.yaml) ];
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = commonOptions // {
        operator = lib.mkOption {
          type = lib.types.enum (lib.attrNames engines.operators);
          description = "Which operator, from the catalogue. Available: ${lib.concatStringsSep ", " (lib.attrNames engines.operators)}.";
        };
      };
    }));
  };

  options.nixdb.instances = lib.mkOption {
    default = { };
    description = ''
      Database instances, keyed by a name of your choosing. ONE ENTRY PER RUNNING DATABASE, not one
      per engine: several majors of one engine routinely run side by side and permanently, so the
      key is a name like the version it runs rather than the name of the engine.

      Each names an engine from the catalogue and the version it runs. What happens next depends on
      the engine, and the fork is read from the catalogue rather than declared here: a self-managed
      engine is rendered in full through the app grammar, while an operator-managed engine's
      instance is a custom resource whose text is taken as a value.
    '';
    example = lib.literalExpression ''
      {
        # Two rungs of one ladder. Same engine, same port, different objects, both permanent.
        example-pg-older = {
          engine = "postgres";
          version = "17";
          slot = 34;
          manifests = [ (builtins.readFile ./cluster-older.yaml) ];
        };
        example-pg-newer = {
          engine = "postgres";
          version = "18";
          slot = 35;
          manifests = [ (builtins.readFile ./cluster-newer.yaml) ];
        };

        # A self-managed engine: the grammar renders it, this supplies the values.
        example-mariadb = {
          engine = "mariadb";
          version = "11.8";
          slot = 36;
          state.data.hostPath = "/example/state/mariadb";
          credentials = { secret = "example-mariadb-root"; key = "rootPassword"; };
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = commonOptions // {
        engine = lib.mkOption {
          type = lib.types.enum (lib.attrNames engines.engines);
          description = "Which engine, from the catalogue. Available: ${lib.concatStringsSep ", " (lib.attrNames engines.engines)}.";
        };

        version = lib.mkOption {
          type = lib.types.str;
          example = "18";
          description = ''
            Which version of the engine THIS instance runs. Required, with no default anywhere in
            this repository, and that is the encoding of the ladder rather than an oversight: a
            tier runs several majors at once on purpose, so there is no such thing as the current
            version of an engine and nothing here will pick one.

            Used as the image tag for a self-managed engine. For a managed one it is documentation
            -- the operator's own resource names the image -- and it is still required, because an
            instance whose version is not written down anywhere is the thing this rule exists to
            prevent.
          '';
        };

        credentials = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule {
            options = {
              secret = lib.mkOption {
                type = lib.types.str;
                description = "NAME of an existing Secret holding the engine's root credential.";
              };
              key = lib.mkOption {
                type = lib.types.str;
                description = "Which key inside that Secret carries it.";
              };
            };
          });
          default = null;
          description = ''
            The engine's root credential, by reference. WHICH ENVIRONMENT VARIABLE it is injected
            as comes from the catalogue, because that is a property of the engine; which Secret
            holds it and under which key is a value.

            Refused on an engine that reads no root credential from its environment -- see that
            engine's own note for how its credentials are actually established, which for at least
            one of them is a genuinely different mechanism rather than a different variable name.
          '';
        };
      };
    }));
  };

  options.nixdb.tools = lib.mkOption {
    default = { };
    description = ''
      Tier tooling running in the cluster, keyed by a name of your choosing. Something that
      CONNECTS to the engines rather than being one: it stores nothing anybody depends on, and it
      is empty without them.

      Rendered in full through the app grammar, like a self-managed engine -- it is an image with a
      port and a directory.
    '';
    example = lib.literalExpression ''
      {
        example-browser = {
          tool = "whodb";
          version = "0.59.0";
          exposure = "nb";
          state.data.hostPath = "/example/state/browser";
          envFromSecrets = [ "example-browser-connections" ];
        };

        # The same kind of workload, idled. Both terms are decisions rather than facts: whether it
        # sleeps, and which front wakes it. Whether it CAN sleep is the catalogue's answer.
        example-diagram = {
          tool = "chartdb";
          version = "1.0.0";
          exposure = "nb";
          scaling = "scale-to-zero";
          wake = "keda";
          # Slower disks than whatever the catalogue's budget was measured on. The timing only:
          # the path and the port this probe asks on are not reachable from here.
          probeBudget.readiness.failureThreshold = 36;
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = commonOptions // {
        tool = lib.mkOption {
          type = lib.types.enum (lib.attrNames engines.tooling);
          description = "Which tool, from the catalogue. Available: ${lib.concatStringsSep ", " (lib.attrNames engines.tooling)}.";
        };

        version = lib.mkOption {
          type = lib.types.str;
          description = "Which version this instance runs, used as the image tag. Required, and defaulted nowhere.";
        };
      };
    }));
  };

  # ── Computed, read-only ───────────────────────────────────────────────────────────────────────
  options.nixdb.slots = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.unsigned;
    readOnly = true;
    default = lib.listToAttrs
      (map (x: lib.nameValuePair x.name x.w.slot) (lib.filter (x: x.w.slot != null) allWorkloads));
    defaultText = lib.literalExpression "every declared workload that claims a slot";
    description = ''
      workload -> the position it claims, for every workload in the tier that claims one. Nothing
      is rendered from it here: what an address looks like is the private layer's business, and
      this is what that layer reads to build one.
    '';
  };

  options.nixdb.operatorCharts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
    readOnly = true;
    default = lib.mapAttrs (_: w: (engines.operators.${w.operator}).chart) operators;
    defaultText = lib.literalExpression "the upstream chart coordinates of every declared operator";
    description = ''
      workload -> `{ repo, name }` for the upstream Helm chart that delivers it. Published rather
      than rendered, and WITHOUT a version, because a version and its digest change every release
      and are pinned by whoever deploys the chart -- a copy here would be a second pin that nothing
      keeps honest. A consumer building its own chart application reads the coordinates from here
      and supplies the parts that move.
    '';
  };

  options.nixdb.renderedByGrammar = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) byGrammar;
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = "Workloads rendered through the app grammar, in full.";
  };

  options.nixdb.renderedDirectly = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) directly;
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = ''
      Workloads rendered one level BELOW the app grammar, because what they deliver is a whole
      object rather than a container -- an operator's chart output, or the custom resource that is
      a managed instance.

      Read-only, and the point of it is that it is COUNTABLE: this is the tier's untyped surface,
      and a boundary nobody measures becomes the architecture.
    '';
  };

  config = {
    # THE WHOLE CLUSTER-FACING RENDER, and there is nothing else: every object this tier produces
    # that can be described as an app is described as one, in somebody else's vocabulary.
    nixk3s.apps = lib.listToAttrs (map (x: lib.nameValuePair x.name (mkGrammarApp x)) byGrammar);

    applications = lib.listToAttrs (map (x: lib.nameValuePair x.name (mkDirectApp x)) directly);

    # THE POSITIONS THE GRAMMAR CANNOT SEE. Everything rendered one level below the grammar holds a
    # real slot — an operator's, a managed instance's — while never appearing in `nixk3s.apps`, which
    # is where the band model counts occupancy from. Left unsaid, the fleet's own report advertises
    # those numbers as FREE while they are live addresses, and the next allocation collides with a
    # database.
    #
    # `addressingOf` already hands the grammar-rendered half its slot; this is the other half, and it
    # is the same fact told to the same model in the only other way the model accepts. Conditional on
    # `origin` for the same reason `addressingOf` is: with no origin there is no band to be counted
    # in, and claiming a position in a space this tier was never bound to would be a lie rather than
    # a reservation.
    #
    # THE SET IS "NOT RENDERED BY THE GRAMMAR", NOT "RENDERED DIRECTLY", and the difference is a real
    # one: an operator declared with empty `manifests` renders nowhere in this module at all, yet it
    # still HOLDS its position — ours is the cnpg at slot 100, whose chart ships from an application
    # of the consumer's own. Keying this off `directly` would have left exactly that number reading
    # free while an operator occupies it. A slot is held by the decision to hold it, never by whether
    # this module happens to emit an object for it.
    nixk3s.addressing.reservations = lib.optionalAttrs (platform.origin != null) (
      lib.listToAttrs (map
        (x: lib.nameValuePair x.name {
          slot = x.w.slot;
          origin = platform.origin;
          note =
            if x.kind == "operator"
            then "${x.w.operator} operator, not rendered by the app grammar"
            else "${x.w.engine} ${x.w.version}, a custom resource rendered below the app grammar";
        })
        (lib.filter (x: x.w.slot != null && !(lib.elem x byGrammar)) allWorkloads))
    );

    nixidy.assertions =
      instanceAssertions ++ toolAssertions ++ classAssertions ++ orderingAssertions ++ tierAssertions;
    nixidy.warnings = warnings;
  };
}
