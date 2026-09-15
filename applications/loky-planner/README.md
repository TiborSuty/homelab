# Loky Planner

Argo CD deploys the web frontend, API, media worker, mock publishing worker,
outbox dispatcher, Redis, and a dedicated PostgreSQL 16/PostGIS database in
`loky-planner`. Database and Redis volumes use retained Longhorn storage.
MinIO stores private objects in `loky-media` using bucket-scoped credentials.

Browser URL: `http://loky-planner.loky-planner.homelab.internal`.
Connect the device to NetBird; the `dashboard-clients` policy controls access
to this private route. Homepage links to this address. The application currently
uses one configured user (`loky-user`); the publishing provider is still a mock.

The optional public address, `https://tiborsuty-loky-planner.eu1.netbird.services`,
retains NetBird account SSO. Its Cloud authentication service currently returns
`authentication service unavailable`, so browser access and signed uploads use
the private address.

Nginx serves the compiled frontend with SPA fallback and forwards GraphQL,
media file, upload, and queue-dashboard requests to the API. Signed S3 uploads
use `/loky-media/` on the same private hostname. Nginx preserves the hostname,
bucket path, and query string required by the signature. The bucket remains
private, and unsigned requests are rejected by MinIO. Keeping uploads on the
same origin keeps uploads on the device's authenticated NetBird connection.

## First deployment

From the homelab repository:

```sh
python3 bootstrap/create-loky-planner-secrets.py
kubectl --kubeconfig .local/kubeconfig apply -f applications/loky-planner/storage-init.yaml
kubectl --kubeconfig .local/kubeconfig -n minio wait --for=condition=Complete job/loky-planner-storage-init --timeout=45s
```

The helper retains private values in `.local/loky-planner.env` (mode 600),
creates database/runtime Secrets, copies read-only registry pull access into
the application namespace, and gives the storage initialization Job its own
MinIO credentials. The Job uses existing MinIO root credentials only for
provisioning. It is deliberately outside the application Kustomization.

Build the images from the adjacent `loky-planner` source repository:

```sh
docker buildx build --platform linux/amd64 --load -f infrastructure/docker/Dockerfile.server -t loky-server:latest .
docker buildx build --platform linux/amd64 --load --secret id=mapbox_browser_token,env=MAPBOX_ACCESS_TOKEN -f infrastructure/docker/Dockerfile.web -t loky-web:latest .
```

Provide the existing public Mapbox browser token to the build process; it is
embedded in the frontend bundle. Do not provide a secret Mapbox server token.

Back in the homelab repository:

```sh
python3 bootstrap/push-loky-planner-images.py
kubectl kustomize applications/loky-planner
```

The push helper uses a temporary non-root Pod with the private registry CA,
dedicated push access, and a hostname mapping. It removes its temporary
resources and pins both deployment images by their registry digest. Commit
the manifests and Argo application registration to `main` for reconciliation.
Terraform under `infrastructure/netbird/cloud/` owns the SSO HTTPS proxy;
apply it after the application NetworkResource is Ready.

## Validation and upgrades

```sh
kubectl --kubeconfig .local/kubeconfig -n loky-planner get pods,pvc,cluster,networkresource
kubectl --kubeconfig .local/kubeconfig -n argocd get application loky-planner
```

The API exposes `/healthz` for liveness and `/readyz` for database readiness.
Verify the browser can create a hike, upload media, load generated thumbnails,
and schedule a mock post. Repeat the image builds and push helper for upgrades,
then commit the new digests; Argo CD performs the rollout.

This deployment starts with an empty database and bucket. Existing local
PostgreSQL/MinIO data is untouched. Migrating it requires a database dump and
object copy. Longhorn replication is not an off-cluster backup; database and
media backup destinations must be configured before relying on this deployment
as the only copy of personal data.
