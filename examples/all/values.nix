# Placeholder values for the cluster module — the file that makes the render check real.
# `nix flake check` renders the whole tier from here, so a module that stops evaluating, or that
# grows a required value nobody supplies, fails in CI rather than in somebody's cluster.
#
# NOTHING HERE IS REAL. Every namespace, path, name, number and image is invented for this file,
# and no credential appears in any form — only the NAMES of Secrets that would hold them.
#
# The declarations are chosen to cover the paths that differ in what gets RENDERED rather than
# merely in what evaluates:
#
#   - an operator, delivering whole objects, sitting BELOW the instances it manages;
#   - a LADDER: two majors of one engine, side by side, permanently, both listening on the same
#     port in two different objects;
#   - a self-managed engine, rendered in full by the app grammar, on node-path state, with a root
#     credential by reference and the namespace anchor;
#   - a third engine whose wire protocol is not its own product, exposing three ports and writing
#     three separate directories;
#   - tier tooling, in its own namespace, reachable to something outside the cluster, consuming a
#     Secret wholesale and pinned by digest.
{
  # Required by the nixidy environment itself, not by any module here.
  nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
  nixidy.target.branch = "main";

  # A cluster fact the app grammar refuses to guess: which node holds the directories that
  # node-path state lives on. Set once here instead of on every engine.
  nixk3s.appPlatform.hostPathNodeSelector = { "kubernetes.io/hostname" = "example-node"; };

  # The band model, with the layout a consumer would supply. Every value is invented: the model
  # ships no band, no base and no binding, because which category owns which run of the number
  # space is the shape of somebody's fleet.
  nixk3s.addressing = {
    enable = true;
    bands.example-data = {
      base = 96;
      size = 32;
      description = "the data tier";
    };
    bindings.nixdb = "example-data";
  };

  nixdb.clusterPlatform = {
    namespace = "example-dbs";
    project = "example-data";
    # Hands the grammar-rendered workloads' slots to the band model above. Null (the default)
    # everywhere that model is not part of the render.
    origin = "nixdb";
  };

  # The operator. Its slot is the position immediately BELOW the instances it manages — declared
  # here in that order deliberately, because the module refuses the inverted one.
  nixdb.operators.example-pg-operator = {
    operator = "cnpg";
    slot = 100;
    # Stands in for the operator's own chart output. A real consumer reads its rendered chart in
    # here, or leaves this empty and deploys the chart from its own application — the coordinates
    # to build one with are published at `nixdb.operatorCharts`.
    manifests = [
      ''
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: example-pg-operator
          namespace: example-dbs
      ''
      ''
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: example-pg-operator
          namespace: example-dbs
        spec:
          replicas: 1
          selector:
            matchLabels:
              app.kubernetes.io/name: example-pg-operator
          template:
            metadata:
              labels:
                app.kubernetes.io/name: example-pg-operator
            spec:
              serviceAccountName: example-pg-operator
              containers:
                - name: manager
                  image: registry.example.com/example-org/example-pg-operator:0.0.0
      ''
    ];
  };

  nixdb.instances = {
    # THE LADDER, rung one. An older major that the applications qualified against stay on.
    example-pg-older = {
      engine = "postgres";
      version = "17";
      slot = 101;
      manifests = [
        ''
          apiVersion: postgresql.cnpg.io/v1
          kind: Cluster
          metadata:
            name: example-pg-older
            namespace: example-dbs
          spec:
            instances: 1
            imageName: registry.example.com/example-org/example-postgres:17
            storage:
              size: 1Gi
        ''
      ];
    };

    # THE LADDER, rung two. The newest major, which new applications onboard to. Same engine, same
    # port, a different object, and both are permanent.
    example-pg-newer = {
      engine = "postgres";
      version = "18";
      slot = 102;
      manifests = [
        ''
          apiVersion: postgresql.cnpg.io/v1
          kind: Cluster
          metadata:
            name: example-pg-newer
            namespace: example-dbs
          spec:
            instances: 1
            imageName: registry.example.com/example-org/example-postgres:18
            storage:
              size: 1Gi
        ''
      ];
    };

    # A self-managed engine: one container, one data directory, rendered in full by the grammar.
    # Anchors the shared namespace, because it is rendered by the grammar and therefore stamps the
    # protection a namespace holding databases needs.
    example-mysql = {
      engine = "mariadb";
      version = "11.8";
      slot = 107;
      createNamespace = true;
      # Deliberately tag-only, so the render sees the grammar's unpinned-image warning fire as well
      # as the pinned path further down.
      state.data.hostPath = "/example/apps/dbs/mysql";
      credentials = { secret = "example-mysql-root"; key = "rootPassword"; };
    };

    # Three ports, three separate state directories, and a wire protocol that is not its own
    # product. Its extra JVM configuration is capacity plus the indirection its own note describes,
    # so it arrives as plain environment from here.
    example-multimodel = {
      engine = "arcadedb";
      version = "26.5.1";
      slot = 108;
      state = {
        data.hostPath = "/example/apps/dbs/multimodel/databases";
        config = { hostPath = "/example/apps/dbs/multimodel/config"; hostPathType = "DirectoryOrCreate"; };
        backup = { hostPath = "/example/apps/dbs/multimodel/backups"; hostPathType = "DirectoryOrCreate"; };
      };
      credentials = { secret = "example-multimodel-root"; key = "rootPassword"; };
      env.JAVA_OPTS = "-Darcadedb.server.rootPassword=$(ROOT_PW) -Darcadedb.server.databaseDirectory=/arcade_db";
    };
  };

  # Tier tooling: its own namespace, reachable to peers of a private overlay, one directory, and a
  # Secret carrying every connection it makes. Pinned by digest, which is what the grammar asks for
  # and what the engine above deliberately does not do.
  nixdb.tools.example-browser = {
    tool = "whodb";
    version = "0.0.0";
    image = "registry.example.com/example-org/example-browser:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000";
    namespace = "example-browser";
    createNamespace = true;
    exposure = "nb";
    slot = 110;
    state.data.hostPath = "/example/apps/dbs/browser";
    envFromSecrets = [ "example-browser-connections" ];
  };
}
