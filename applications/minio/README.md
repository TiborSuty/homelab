# MinIO

MinIO provides an S3-compatible API for applications in the cluster. This is a
single MinIO server backed by a 50 GiB ReadWriteOnce Longhorn volume. Longhorn
keeps three synchronous replicas, one per storage node, so MinIO itself does not
duplicate the data a second time.

The server uses the free Chainguard MinIO image because upstream MinIO stopped
publishing maintained community container images. The image is pinned by digest
for reproducible deployment. Review and update that digest deliberately when a
new Chainguard build is adopted.

## Credentials

The public repository does not contain the MinIO root credentials. Create the
Kubernetes Secret and the ignored local credentials file before the first sync:

```sh
./bootstrap/create-minio-secret.sh
```

The credentials are stored in `.local/minio.env` with mode `600`. Root
credentials are for administration only. Applications should receive their own
access keys and bucket-scoped policies.

## Endpoints

Applications in Kubernetes use the internal S3 endpoint:

```text
http://minio.minio.svc.cluster.local:9000
```

Keep the console private and access it through a port-forward:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n minio port-forward svc/minio-console 9001:9001
```

Open <http://localhost:9001> and sign in with the values from
`.local/minio.env`. The S3 API can similarly be forwarded from `svc/minio` on
port `9000`.

## Durability

Longhorn replication protects against a normal node or disk failure, but it is
not an off-cluster backup. A full cluster loss, accidental object deletion, or
corruption replicated to every Longhorn copy still requires an independent S3
or NAS backup target.
