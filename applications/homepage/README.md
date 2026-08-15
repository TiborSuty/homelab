# Homepage

Homepage is the private start page for homelab services. Its configuration is
stored in `configmap.yaml`, and its read-only service account lets it display
Kubernetes node and workload statistics. It has no ingress or authentication
and is exposed only through a local port-forward.

Start Homepage and every UI linked from its service cards:

```sh
./bootstrap/port-forward-uis.sh
```

Open <http://localhost:3001>. Stop the script with `Ctrl-C` to close every
forward. Add new non-secret service cards to `services.yaml` inside the
ConfigMap. API keys and passwords must not be committed to this public
repository.
