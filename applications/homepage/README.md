# Homepage

Homepage is the private start page for homelab services. Its configuration is
stored in `configmap.yaml`, and its read-only service account lets it display
Kubernetes node and workload statistics. It has no authentication and is
available from the trusted home LAN through any cluster node:

- <http://192.168.187.201:30301>
- <http://192.168.187.202:30301>
- <http://192.168.187.203:30301>

All three addresses route to the same Homepage Service. Keep router port
`30301` closed so that the unauthenticated dashboard is not exposed to the
internet.

An external Caddy server can use any node address as its upstream. Override the
upstream `Host` header with a value already allowed by Homepage:

```caddyfile
http://dashboard.home.arpa {
    reverse_proxy 192.168.187.201:30301 {
        header_up Host homepage:3000
    }
}
```

Add `dashboard.home.arpa` to local DNS with the Caddy server's LAN address. The
direct NodePort addresses remain available if Caddy is offline. This example
uses HTTP so clients do not need to trust Caddy's private certificate authority.

For localhost-only access, the existing forwarding script remains available:

Start Homepage and every UI linked from its service cards:

```sh
./bootstrap/port-forward-uis.sh
```

Open <http://localhost:3001>. Stop the script with `Ctrl-C` to close every
forward. Add new non-secret service cards to `services.yaml` inside the
ConfigMap. API keys and passwords must not be committed to this public
repository.
