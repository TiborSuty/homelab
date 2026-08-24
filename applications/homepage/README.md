# Homepage

Homepage is the private start page for homelab services. Its configuration is
stored in `configmap.yaml`, and its read-only service account lets it display
Kubernetes node and workload statistics. Its `ClusterIP` Service remains
private. NetBird Cloud publishes the SSO-protected HTTPS entry point:

- <https://tiborsuty-homepage.eu1.netbird.services>

When connected to NetBird, Homepage is also available directly through its
private `ClusterIP` Service:

- <http://homepage.homepage.homelab.internal:3000>

The service cards use the corresponding SSO-protected NetBird Cloud URLs. No
router port forwarding or Kubernetes NodePort is required.

For localhost-only access, the existing forwarding script remains available:

Start Homepage and every UI linked from its service cards:

```sh
./bootstrap/port-forward-uis.sh
```

Open <http://localhost:3001>. Stop the script with `Ctrl-C` to close every
forward. Add new non-secret service cards to `services.yaml` inside the
ConfigMap. API keys and passwords must not be committed to this public
repository.
