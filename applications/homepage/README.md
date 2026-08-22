# Homepage

Homepage is the private start page for homelab services. Its configuration is
stored in `configmap.yaml`, and its read-only service account lets it display
Kubernetes node and workload statistics. Its ClusterIP Service is private;
in-cluster Caddy makes it available from the trusted home LAN through any
cluster node:

- <http://192.168.187.201:30080>
- <http://192.168.187.202:30080>
- <http://192.168.187.203:30080>

All three addresses route to the Caddy Service, which proxies to Homepage over
cluster DNS. Keep router port `30080` closed so that the unauthenticated
dashboard is not exposed to the internet. Caddy's manifests and routing config
are in `../../infrastructure/caddy/`.

For localhost-only access, the existing forwarding script remains available:

Start Homepage and every UI linked from its service cards:

```sh
./bootstrap/port-forward-uis.sh
```

Open <http://localhost:3001>. Stop the script with `Ctrl-C` to close every
forward. Add new non-secret service cards to `services.yaml` inside the
ConfigMap. API keys and passwords must not be committed to this public
repository.
