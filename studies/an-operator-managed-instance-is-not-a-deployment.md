# An operator-managed instance is not a Deployment, and the app grammar cannot render one

**Finding.** The sibling app grammar this repository consumes renders a Deployment for every app,
unconditionally, from a required `image`. There is no declaration it accepts that produces an
Application carrying *only* passed-through objects. Two things the database tier genuinely contains
are exactly that shape, so both are rendered one level below the grammar, on the renderer's own
`applications.<name>` — and the module says so out loud rather than quietly rendering an empty
Deployment beside them.

## Why it came up

The tier has four kinds of workload and only two of them are apps in the grammar's sense:

| Workload | Is it an image with a port? | How it is rendered |
|---|---|---|
| A self-managed engine | yes | the grammar, in full |
| Tier tooling (a browser) | yes | the grammar, in full |
| An operator's delivery | no — a vendor chart's whole object set | below the grammar |
| An instance of a managed engine | no — a custom resource | below the grammar |

The last row is the interesting one. An instance of an operator-managed engine *is* a `Cluster`
object: the operator reads it and creates the pod, the Service, the credential Secret and the
volume. There is no container to declare, because the declaration is not of a container.

## Evidence

From the grammar's own renderer, every application it produces:

```nix
resources = {
  deployments.${app.name} = mkDeployment app;
  services.${app.name} = lib.mkIf (app.ports != { }) (mkService app);
  namespaces.${app.namespace} = lib.mkIf app.createNamespace (mkNamespace app);
};
yamls = app.raw;
```

`services` and `namespaces` are conditional. `deployments` is not, and `image` is a required option
with no default, so there is no way to ask for the `yamls` half alone. Routing a custom resource
through the grammar's escape hatch would therefore also render a Deployment for an image nobody
wants, with a selector matching no pods — an object that is not merely useless but actively
misleading in a cluster view.

Confirmed in the rendered tree: the two rungs of the example ladder render exactly one file each,
and `checks/cluster-render.nix` asserts the *absence* of a Deployment and a Service for both.

```
example-pg-older/Cluster-example-pg-older.yaml
example-pg-newer/Cluster-example-pg-newer.yaml
```

## What it changed

1. `modules/cluster.nix` forks on the catalogue's `managed` field, not on anything the consumer
   declares: whether an engine has an operator between the declaration and the process is a fact
   about the engine.
2. The two shapes the grammar cannot express take their object text as a **value** (`manifests`),
   for a second reason beyond this one: a custom resource's schema belongs to the operator's own
   API version and a chart's object set to its vendor's release, so a copy rendered here would be a
   permanently lagging second opinion about somebody else's API.
3. `nixdb.renderedDirectly` is published, read-only, so the untyped side of the tier is
   **countable**. A boundary nobody measures becomes the architecture.
4. Two guards follow from it, both asserted in the failing direction. A managed instance with no
   `manifests` is refused, because an Application with nothing in it syncs happily and creates no
   database. A workload rendered below the grammar may not create a namespace, because the
   protection the grammar stamps on a Namespace it creates — the annotation that keeps it from
   being read as no-longer-desired and cascade-deleted — is not applied to one created here, and a
   namespace full of databases is the worst possible place to discover that.

## What would change this

An `image = null` path in the grammar, meaning "render no Deployment". That is the grammar's
decision to make, not this repository's, and until it exists the split above is the honest shape
rather than a workaround.
