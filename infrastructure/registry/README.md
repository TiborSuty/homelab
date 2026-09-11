# Zot container registry

Zot provides the private OCI registry for application images at:

```text
https://registry.homelab.internal
```

The registry is reachable from all Talos nodes through the Cilium L2
LoadBalancer address `192.168.187.211`. Talos maps the hostname statically, so
image pulls do not depend on NetBird or cluster DNS. Zot runs as one restricted
StatefulSet replica backed by a retained 20 GiB Longhorn volume.

The ingress policies permit Cilium's `world` identity for LAN clients and its
`remote-node` identity for containerd and cross-node LoadBalancer forwarding.
The LoadBalancer address is only announced on the LAN, and registry
authentication still applies to every request. Selected application namespaces
are allowed separately for direct in-cluster access.

## Versions and trust

- Zot: `v2.1.21`
- Image index digest: `sha256:6b69512c00dceaad05b1144e6079aac6aa7309d7fd200f9947ecb1de09cf48c8`
- TLS: private registry CA bootstrapped outside Git; public CA certificate is
  tracked at `talos/registry-ca.crt`

The Zot image itself remains on its upstream GHCR source. This avoids making
the registry dependent on an image stored only inside itself.

## Credentials

Generate the private CA and the three registry identities before the first
Argo CD sync:

```sh
./bootstrap/create-registry-secrets.sh
```

The helper creates these Secrets in `registry`:

- `registry-ca`: private CA certificate and key for cert-manager;
- `zot-auth`: bcrypt hashes consumed by Zot;
- `registry-pull`: a Docker configuration containing read-only pull access.

Plaintext credentials and the private CA key are stored only in ignored files
under `.local/`, with mode `600`. Back those files up securely outside the
cluster. Git contains only the public CA certificate.

The identities have intentionally separate permissions:

| Identity | Permissions | Scope |
| --- | --- | --- |
| `registry-admin` | read, create, update, delete | all repositories |
| `loky-ci-push` | read, create, update | `loky/**` |
| `loky-cluster-pull` | read | `loky/**` |

## Talos configuration

Generate and validate the node configurations after the public CA certificate
exists:

```sh
./talos/render-configs.sh
```

The renderer adds a `StaticHostConfig` for `registry.homelab.internal` and a
`RegistryTLSConfig` containing the registry CA. Apply the rendered configs one
node at a time, checking Kubernetes readiness between nodes.

## Verification

The unauthenticated registry API must challenge for credentials:

```sh
curl --resolve registry.homelab.internal:443:192.168.187.211 \
  --cacert talos/registry-ca.crt \
  https://registry.homelab.internal/v2/
```

Use credentials from `.local/registry.env` without printing them. Verify an
authenticated request, push an image under `loky/`, and finally start a Pod
which references that image and `registry-pull`. A successful Pod start proves
node reachability, hostname resolution, TLS trust, credentials, and registry
storage together.

Longhorn replication is not an off-cluster backup. Back up the registry data
or retain a reproducible external source for every important image.
