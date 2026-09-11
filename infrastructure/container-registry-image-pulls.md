# Private registry image pulls on Talos

A container image must be downloaded before its Pod can start. The download is
therefore performed by the kubelet and containerd on the selected Talos node,
not by the application container.

## Image pull sequence

Given a workload such as:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: registry-pull
      containers:
        - name: api
          image: registry.homelab.internal/loky/server@sha256:abc123
```

Kubernetes follows this sequence:

```text
Argo CD creates Deployment
          |
Scheduler selects a node
          |
Kubelet asks containerd for the image
          |
containerd connects to the registry
          |
containerd verifies the TLS certificate
          |
containerd authenticates with registry-pull
          |
Image downloads and the container starts
```

The registry must pass three independent checks: network reachability, TLS
trust, and registry authorization.

## 1. Network reachability

Every Talos node must be able to connect directly to the registry endpoint,
for example:

```text
registry.homelab.internal:443
```

A NetBird `NetworkResource` primarily gives NetBird clients access to a
Kubernetes Service. It does not automatically make that Service reachable or
resolvable by containerd on each Talos host.

For an in-cluster registry, give it a stable Cilium LoadBalancer address and a
DNS name that all nodes can resolve:

```text
registry.homelab.internal
        |
        v
Cilium LoadBalancer IP
        |
        v
Registry Service and Pod
```

This cluster reserves `192.168.187.211` for the registry. The address was not
present in ARP and did not answer ICMP before allocation; it must also remain
outside the router's DHCP allocation range.

## 2. TLS trust

After connecting, containerd verifies that the registry certificate is valid
for `registry.homelab.internal` and was issued by a trusted certificate
authority.

A certificate issued by a normal public CA is usually already trusted. If the
registry uses an internal homelab CA, add that CA to every Talos node through
persistent Talos registry TLS configuration. Otherwise image pulls fail with
an error similar to:

```text
x509: certificate signed by unknown authority
```

This is Talos configuration because host-level containerd performs the TLS
verification before the application Pod exists. Adding the CA only inside a
Pod is too late. Do not use `insecureSkipVerify` as the permanent solution.

See the
[Talos RegistryTLSConfig documentation](https://docs.siderolabs.com/talos/v1.13/reference/configuration/cri/registrytlsconfig).

## 3. Registry authorization

After TLS verification, the registry checks whether the requester may pull the
image. Kubernetes supplies credentials from `imagePullSecrets` in the Pod
specification.

The referenced Secret normally has type:

```text
kubernetes.io/dockerconfigjson
```

It must exist in the same namespace as the workload. Use a dedicated registry
identity with read-only access to the required repositories, for example:

```text
Identity:   loky-cluster-pull
Permission: pull
Scope:      loky/*
```

The build pipeline should use a separate identity with push permission:

```text
Identity:   loky-ci-push
Permission: push and pull
Scope:      loky/*
```

Create these credentials interactively and keep their values out of Git. The
pull Secret provides registry authentication; it does not configure TLS trust.

See the
[Kubernetes private registry documentation](https://kubernetes.io/docs/concepts/containers/images/#using-a-private-registry).

## Diagnosing failures

| Failed check | Typical symptom |
| --- | --- |
| Registry is unreachable | timeout, connection refused, or no route |
| DNS cannot resolve the hostname | `no such host` |
| Talos does not trust the registry CA | `x509: certificate signed by unknown authority` |
| Pull credentials are missing or wrong | `401 Unauthorized` |
| Image name, tag, or digest is absent | `manifest unknown` |
| Pull failures continue | Pod enters `ImagePullBackOff` |

Troubleshoot in that order: reachability, DNS, TLS trust, credentials, then the
image reference.

## Registry bootstrap dependency

If the registry itself runs inside Kubernetes, it must start before other Pods
can pull application images from it. Keep the registry's own image referenced
from an external upstream registry, or guarantee that it is cached on every
node. Do not make the registry depend exclusively on an image stored inside
itself.

Initially use the private registry only for application images such as:

```text
registry.homelab.internal/loky/server@sha256:...
registry.homelab.internal/loky/web@sha256:...
```

Keep critical cluster images such as Cilium, Argo CD, and Longhorn on their
existing pinned upstream sources until registry bootstrap and recovery have
been designed and tested.

## Ownership in this repository

```text
Talos patches = registry CA trust and persistent node configuration
Argo CD       = registry workload, Service, storage, and application workloads
Kubernetes Secret = namespace-scoped image pull credentials
kubectl       = observation, validation, and emergency operations
```

The implementation is documented in [`registry/README.md`](registry/README.md).
