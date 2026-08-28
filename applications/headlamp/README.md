# Headlamp

Headlamp is the read-only Kubernetes resource dashboard for this cluster. Argo
CD deploys the official Helm chart into the `headlamp` namespace. The pod uses
an aggregated read-only ClusterRole: it can inspect normal workloads plus
cluster-scoped nodes, namespaces, storage, CRDs, and metrics, but it cannot
mutate resources or read Kubernetes Secrets.

NetBird is the authentication and network boundary. The Headlamp server uses
its read-only ServiceAccount automatically only because neither its ClusterIP
Service nor its public endpoint bypasses the approved NetBird access paths.
Do not expose the Service with a public LoadBalancer, NodePort, or unauthenticated
proxy while `unsafeUseServiceAccountToken` is enabled.

The SSO-protected HTTPS endpoint is:

- <https://tiborsuty-headlamp.eu1.netbird.services>

For localhost-only access:

```sh
kubectl --kubeconfig .local/kubeconfig \
  --namespace headlamp port-forward service/headlamp 4466:80
```

Then open <http://localhost:4466>.

Verify the deployment and effective permissions:

```sh
kubectl --kubeconfig .local/kubeconfig \
  --namespace headlamp rollout status deployment/headlamp

kubectl --kubeconfig .local/kubeconfig auth can-i \
  --as=system:serviceaccount:headlamp:headlamp list nodes

kubectl --kubeconfig .local/kubeconfig auth can-i \
  --as=system:serviceaccount:headlamp:headlamp get secrets --all-namespaces
```
