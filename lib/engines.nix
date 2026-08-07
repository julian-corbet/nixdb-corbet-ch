#
# The cluster catalogue: what the database tier can run. Three groups, because the tier genuinely
# contains three kinds of thing and flattening them would make the model lie:
#
#   `operators`  software that MANAGES instances of an engine. It is a workload itself, and the
#                instances it reconciles are custom resources rather than workloads.
#   `engines`    a database that runs as its own container -- self-managed, one image, one data
#                directory, no controller between the declaration and the process.
#   `tooling`    something that CONNECTS to the engines from inside the cluster rather than being
#                one. It has no wire protocol of its own and nothing depends on it for storage.
#
# THE PLACEMENT RULE, stated as a boundary rather than a list, in the same shape nixsh's
# lib/tools.nix and nixagent's lib/agents.nix state theirs:
#
#   Does the thing STORE the data other software depends on, manage something that does, or exist
#   only to inspect one?
#     yes -> it belongs here
#     no  -> it belongs to whichever repo owns the thing it actually is
#
# "Has a database in it" is NOT the test, and that clause matters more than it looks: nearly every
# self-hosted application ships or requires a database, and if proximity to one were the test this
# catalogue would swallow the whole application layer. The test is whether the thing IS the storage
# tier. A wiki that keeps its pages in Postgres is a wiki; the Postgres is ours.
#
# ── TWO NEIGHBOURS THIS RULE IS DRAWN AGAINST ──────────────────────────────────────────────────
#
#   - the application cookbook (nixapps). That repo describes ORDINARY self-hosted applications:
#     things a person opens, which sit at the leaves of the dependency graph and CONSUME a
#     database. Everything here sits at the root of that graph: an engine is what other workloads
#     depend on, and an operator is what the engine depends on. The cookbook says of itself that
#     it will never grow "a storage provisioner, a device plugin, a project renderer" -- a
#     database operator is the same kind of thing, infrastructure rather than an app, and it has no
#     home there by that repo's own contract.
#
#   - schema DIAGRAMMING (chartdb and its kind) is deliberately NOT here, and naming it is the
#     point of this paragraph. A diagramming tool reads a schema once and draws it; it is a design
#     surface for whoever writes the schema, not an operational surface for whoever runs the
#     engine. Nothing in the tier depends on it, and it depends on the tier only in the way a
#     screenshot depends on a screen. It sits in a different band of the cluster and is not claimed
#     by this repository in any form.
#
# The one entry that sits closest to that boundary is the database BROWSER in `tooling` below, and
# the difference is not the direction it points -- both read a schema -- but what it is for: a
# browser is how the tier is operated (open a live database, run a statement, look at what an
# application actually wrote), so it is useless without engines to point at and is deployed
# alongside them, by whoever runs them. A diagram is authored once and read by people who never
# touch the running system.
#
# ── ONE ENGINE IS NOT ONE VERSION ──────────────────────────────────────────────────────────────
#
# The hardest-won thing in this file, and the reason NO ENTRY BELOW CARRIES A VERSION. Real tiers
# run several majors of one engine SIDE BY SIDE, permanently and on purpose: the existing
# applications stay on the major they were qualified against, new ones onboard to the newest, and
# the two are separate objects with separate storage that happen to speak the same protocol on the
# same port. That is not a migration in progress, it is a LADDER, and it is the steady state.
#
# So `version` is a required, defaultless option on every declared instance (see
# ../modules/cluster.nix), a catalogue entry is a KIND of engine rather than a copy of one, and
# nothing here ever asks "which version of postgres is this cluster on" -- a question with no
# answer.
#
# It has a second consequence worth stating separately, because it surprises people: A PORT IS NOT
# AN IDENTITY HERE. Two rungs of one ladder both listen on the engine's canonical port, in two
# different Services, and a third engine below (the multi-model one) additionally speaks the
# Postgres wire protocol on that same number through a plugin. Three objects, one port number,
# no conflict -- because each is a distinct Service and the number is a property of the software,
# not of the network.
#
# ── AN OPERATOR SITS BELOW THE INSTANCES IT MANAGES ────────────────────────────────────────────
#
# Where a fleet maps workloads onto an ordered identity space, an operator takes the position
# immediately BELOW the group it manages, and its instances follow above it. The reason is that the
# ordering is read by humans: an operator and its instances are one subsystem, and the subsystem
# reads correctly only when the thing that reconciles comes before the things it reconciles.
#
# This catalogue models the relationship (`operator` on a managed engine, `manages` on an operator)
# and ../modules/cluster.nix REFUSES an inverted ordering rather than merely documenting it. No
# number appears here or there: which positions exist is the shape of somebody's fleet, and only
# the ordering is universal.
#
# ── FIELDS ─────────────────────────────────────────────────────────────────────────────────────
#
# Shared by every group:
#
#   `image`        container image REPOSITORY, with no tag. The tag is the declared instance's
#                  `version`, which is why it is not here -- see the ladder note above. `null` on a
#                  managed engine, whose image is named inside the operator's own resource.
#   `ports`        named container-side ports, `<name> = <number>`. A container port is a property
#                  of the software rather than of any network, which is the one kind of number a
#                  public declaration may carry.
#   `primaryPort`  which of those the readiness probe watches and the client connects to.
#   `state`        the container-internal paths this software writes, `<name> = <mountPath>`. What
#                  BACKS each one is a value the consumer supplies; where it lands inside the
#                  container is knowledge and lives here.
#   `env`          plain environment the software needs in order to run correctly at all. Never
#                  sizing, never credentials, never an address.
#   `args`         entrypoint arguments in the same spirit.
#   `readiness`    probe timing, in seconds, measured rather than guessed.
#   `note`         what the entry is, and every non-obvious thing about running it.
#
# Group-specific:
#
#   `manages`      (operators) engine keys whose instances this operator reconciles.
#   `chart`        (operators) upstream Helm chart coordinates -- `repo` and `name`, deliberately
#                  WITHOUT a version. See ../modules/cluster.nix for why this repository publishes
#                  the coordinates and renders no chart.
#   `wire`         (engines) which wire protocol a client would speak to it. Not the same as the
#                  product: the multi-model engine below speaks Postgres.
#
#                  A PROTOCOL NAME, NEVER A PACKAGE NAME, and the direction of that reference is
#                  deliberate. This file names no entry of ../lib/clients.nix and must not start
#                  to: a client is a package, packages get assigned to repositories by their
#                  operator, and an engine entry that pointed at one would break here every time a
#                  package moved elsewhere. The reference runs the other way -- a client says which
#                  protocol it speaks -- so this side never has to change.
#   `managed`      (engines) true when instances are custom resources reconciled by an operator
#                  rather than containers. Decides how ../modules/cluster.nix renders an instance,
#                  and it is a hard fork in behaviour rather than a hint.
#   `operator`     (engines) which operator, when `managed`.
#   `rootSecretEnv` (engines) the environment variable that carries the engine's root credential,
#                  or null. The variable's NAME is knowledge; its value is a Secret the consumer
#                  already has, referenced by name and never carried here.
{ ... }:
{
  # ── Operators: software that reconciles instances of an engine ───────────────────────────────
  operators = {
    cnpg = {
      image = null; # delivered by the chart below, not by a single image this repository names
      manages = [ "postgres" ];
      ports = { };
      primaryPort = null;
      state = { };
      env = { };
      args = [ ];
      readiness = null;

      chart = {
        repo = "https://cloudnative-pg.github.io/charts";
        name = "cloudnative-pg";
      };

      note = ''
        CloudNativePG: a Kubernetes operator for PostgreSQL. It reconciles a `Cluster` custom
        resource into the pods, Services, Secrets and PVCs that make up one Postgres instance,
        and owns failover, backup and switchover for it.

        THE CHART CARRIES NO VERSION HERE, on purpose. A chart version and its digest change every
        release and are pinned by whoever deploys it; a copy in this catalogue would be a second,
        lagging pin that nothing keeps honest. What does not change is the repository URL and the
        chart name, so those are the parts published.

        WATCH SCOPE IS CLUSTER-WIDE BY DEFAULT. The operator reconciles instances in every
        namespace, not only its own -- so moving the operator between namespaces does not orphan
        the instances it already manages, and equally, one operator is enough for the whole tier.

        ITS CUSTOM RESOURCE DEFINITIONS ARE LARGE. Large enough that a client-side apply overruns
        the 262144-byte annotation the last-applied state is kept in, which is why every workload
        this repository renders for an operator or a managed instance asks for server-side apply
        and server-side diff. See ../modules/cluster.nix.
      '';
    };
  };

  # ── Engines: the databases themselves ────────────────────────────────────────────────────────
  engines = {
    postgres = {
      image = null; # the instance's own resource names it -- see `managed` below
      managed = true;
      operator = "cnpg";
      wire = "postgres";
      ports.postgres = 5432;
      primaryPort = "postgres";
      state = { };
      env = { };
      args = [ ];
      readiness = null;
      rootSecretEnv = null; # the operator creates and rotates the credential Secret itself

      note = ''
        PostgreSQL, run as instances of the operator above rather than as containers of its own.

        THIS IS THE ENTRY THE LADDER RULE WAS WRITTEN FOR. Several majors run side by side
        indefinitely: applications that were qualified against an older major stay on it, new ones
        onboard to the newest, and both rungs listen on 5432 in two different Services. Declare one
        instance per rung, each with its own `version` and its own storage; nothing in this
        repository has a concept of "the" Postgres.

        AN INSTANCE IS A CUSTOM RESOURCE, NOT A DEPLOYMENT, and that is a fork in how it is
        rendered rather than a detail. The operator owns the pod, the Service, the credential
        Secret and the volume; what is declared is a `Cluster` object describing the desired
        instance. The body of that object is the OPERATOR's API -- versioned with the operator,
        not with this repository -- so it is taken as a value and passed through, exactly the way
        a node path is. See `manifests` in ../modules/cluster.nix.

        STORAGE IS THE OPERATOR'S, hence the empty `state` above: a `Cluster` names its own volume
        size and storage class inside its spec, and a mount declared out here would be a second
        opinion about a directory this repository does not own.
      '';
    };

    mariadb = {
      image = "mariadb";
      managed = false;
      operator = null;
      wire = "mysql";
      ports.mysql = 3306;
      primaryPort = "mysql";
      state.data = "/var/lib/mysql";
      env.MARIADB_ROOT_HOST = "%";
      args = [ ];
      rootSecretEnv = "MARIADB_ROOT_PASSWORD";

      readiness = {
        initialDelaySeconds = 15;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 3;
      };

      note = ''
        MariaDB, the drop-in MySQL-protocol engine. One container, one data directory, single
        writer.

        `MARIADB_ROOT_HOST = "%"` is knowledge, not a loosening anybody chose: the image's default
        confines the root account to connections from localhost, and every consumer inside a
        cluster arrives over TCP from another pod. Without it the engine starts, accepts the
        connection and refuses the login, which reads as a wrong password rather than as a host
        restriction. Reaching it is still governed by the network and by the credential; this only
        stops the account from being useless.

        THE READINESS PROBE HERE IS A TCP CONNECT, and it is weaker than what this engine can
        actually answer. The image ships `healthcheck.sh --connect --innodb_initialized`, which
        distinguishes "the port is open" from "InnoDB finished recovery and will answer queries" --
        a real difference after an unclean stop. That is an exec probe, which the app grammar this
        repository renders through deliberately does not express (its probes are TCP and HTTP), so
        the honest default is the TCP one and the better probe is a typed merge onto the rendered
        Deployment. Said out loud rather than left as a silently weaker default.

        THE INITIAL DELAY IS NOT PADDING. Fifteen seconds is what a cold InnoDB start takes before
        it will answer at all; probing sooner just spends the failure budget on a certainty.
      '';
    };

    mongo = {
      image = "mongo";
      managed = false;
      operator = null;
      wire = "mongodb";
      ports.mongo = 27017;
      primaryPort = "mongo";
      state.data = "/data/db";
      env = { };
      args = [ "--bind_ip_all" ];
      rootSecretEnv = null; # see the note: initial users are created once, not injected per start

      readiness = {
        initialDelaySeconds = 12;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 3;
      };

      note = ''
        MongoDB. One container, one data directory, single writer.

        `--bind_ip_all` because the default binds loopback only, which inside a container means the
        pod can reach it and nothing else can.

        NO `rootSecretEnv`. The image's root-user variables only take effect on an EMPTY data
        directory: they are a first-boot bootstrap, not a credential the engine reads on every
        start. Naming one here would suggest a password can be rotated by changing an environment
        variable, which is exactly the belief that produces an engine nobody can log into. Users
        are created once against the running engine and live in its own catalogue afterwards.

        ENABLING AUTHENTICATION COSTS AN INIT CONTAINER, and it is worth knowing before rather
        than after. `--auth` on a replica set additionally requires `--keyFile`, even for a
        single-member set, because members authenticate to each other with it regardless of how
        many there are. The engine then refuses to start unless that file is owned by the user the
        process runs as and is not group-readable -- and a Secret volume is always root-owned, with
        no option anywhere in Kubernetes to change a Secret file's OWNER (only its group, via
        fsGroup, which the engine's own check then rejects as too permissive). The way every
        real-world chart resolves this: copy the file into an emptyDir in an init container, chown
        it there, and mount that instead. This grammar has no term for an init container, so it is
        a typed merge onto the rendered Deployment.

        A REPLICA SET MEMBER NEEDS A STABLE HOSTNAME, which is a pod-DNS arrangement (a hostname, a
        subdomain and a matching headless Service) rather than anything this vocabulary expresses.
        Also a typed merge, and also worth knowing up front: a member reconfigured onto an unstable
        name is a set that cannot elect after a restart.

        THE READINESS PROBE HERE IS A TCP CONNECT, for the same reason as MariaDB above: a probe
        that actually asks the engine to answer needs credentials and a shell, which is an exec
        probe.
      '';
    };

    arcadedb = {
      image = "arcadedata/arcadedb";
      managed = false;
      operator = null;
      wire = "postgres";
      ports = {
        http = 2480;
        postgres = 5432;
        binary = 2424;
      };
      primaryPort = "http";
      state = {
        data = "/arcade_db";
        config = "/home/arcadedb/config";
        backup = "/arcade_backup";
      };
      env = { };
      args = [ ];
      rootSecretEnv = "ROOT_PW";

      readiness = {
        initialDelaySeconds = 20;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 6;
      };

      note = ''
        ArcadeDB, a multi-model engine (graph, document, key-value, time-series) in one process.

        `wire = "postgres"` IS NOT A TYPO AND NOT THE WHOLE STORY. Its native interfaces are an
        HTTP API on 2480 (which also serves its Studio UI) and a binary protocol on 2424; the
        Postgres wire protocol on 5432 is a PLUGIN, which has to be switched on. It is recorded as
        the `wire` protocol anyway, because it is the interface a person reaches for a shell with --
        this engine and the Postgres ladder are talked to by the same kind of client. `primaryPort`
        is nevertheless the HTTP port rather than the wire port: HTTP is what is always there.

        And it is the third object in a tier that listens on 5432, alongside both rungs of the
        Postgres ladder. Three Services, one port number, no conflict: see this file's header.

        THREE STATE DIRECTORIES, NOT ONE, and they are not interchangeable. `data` holds the
        databases, `config` holds server configuration the process WRITES back (so a read-only
        mount breaks it), and `backup` is where its own backup command lands. A deployment that
        mounts only the first comes up healthy and loses the other two on every restart.

        THE ROOT PASSWORD ARRIVES INDIRECTLY. This engine reads its root password from a JVM system
        property rather than from an environment variable of its own, so the credential is injected
        as `ROOT_PW` from a Secret and then referenced from the JVM options -- which means the JVM
        options string is part of the engine's configuration and not merely tuning. Heap sizing
        belongs in the same string and is deliberately NOT set here: that is capacity, and capacity
        is the consumer's.
      '';
    };
  };

  # ── Tooling: connects to the engines rather than being one ───────────────────────────────────
  tooling = {
    whodb = {
      image = "clidey/whodb";
      ports.http = 8080;
      primaryPort = "http";
      state.data = "/data";
      env = { };
      args = [ ];

      readiness = {
        initialDelaySeconds = 0;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 30;
      };

      note = ''
        A database browser and SQL workspace: connects to several engines at once and gives a
        person a schema tree, a table view and a query editor over live data.

        WHY IT IS TIER TOOLING AND NOT AN ORDINARY APPLICATION. It has no domain of its own. It
        stores nothing anybody depends on, it is deployed by whoever runs the engines, and it is
        empty and pointless without them -- every screen it draws is a rendering of some other
        workload's data. That is the same relationship an operator's control-plane plugin has to
        its operator, which is why both are catalogued in this repository and neither is
        catalogued as an app.

        ITS CONNECTIONS ARE CREDENTIALS, so they are not expressible here in any form. Each one is
        a JSON object with a host, a user and a password, supplied as an environment variable named
        for the engine type and an index; all of them belong in a Secret this repository names and
        never carries. Consumed wholesale (`envFrom`) rather than key by key, because the number of
        connections changes without the declaration changing.

        IT KEEPS SESSION STATE IN A LOCAL FILE, hence the single state directory and the single
        writer that comes with it. It also needs a stable encryption key for that store, in the
        same Secret: replace the key and every saved session becomes unreadable.

        THE READINESS BUDGET IS WIDE ON PURPOSE -- five-second periods and thirty failures, so a
        first start has two and a half minutes. It is a front end with nothing to lose by being
        probed patiently, and an impatient probe on a slow first boot is a restart loop that looks
        like a broken image.
      '';
    };
  };
}
