# AdGuard Home

AdGuard Home provides DNS-level filtering for the `192.168.187.0/24` LAN. A
Cilium L2-announced LoadBalancer exposes DNS at `192.168.187.210` on TCP and
UDP port 53. The router remains the only DHCP server.

## Prerequisites

Reserve `192.168.187.210` outside the router's DHCP pool. Cilium L2
announcements must be enabled before the LoadBalancer address becomes
reachable:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
./bootstrap/install-cilium.sh
```

Verify the network resources and address allocation:

```sh
kubectl get ciliumloadbalancerippool,ciliuml2announcementpolicy
kubectl --namespace adguard-home get service adguard-home-dns
```

## Initial setup

AdGuard Home's interactive first-run wizard requires root. This deployment
instead seeds a restricted-compatible configuration from a ConfigMap and a
locally generated bcrypt password hash. Before the application's first sync,
create the namespace and first-boot Kubernetes Secret without placing the
password or hash in Git:

```sh
./bootstrap/create-adguard-home-secret.sh
```

The initial configuration already sets:

- admin user: `admin` on port `3000`;
- DNS: all interfaces on port `53`;
- DHCP: disabled;
- upstream DNS: Cloudflare and Quad9 over HTTPS;
- DNSSEC: enabled;
- blocking: HaGeZi Pro with daily updates;
- query-log and statistics retention: 30 days.

The bootstrap ConfigMap is copied only when `AdGuardHome.yaml` is absent or
empty. Subsequent UI/API changes remain on the retained configuration volume
and are not overwritten on restart. Change an existing installation's password
through the AdGuard Home UI; changing the bootstrap Secret alone does not
rewrite the live configuration.

Forward the private admin Service locally:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl --namespace adguard-home port-forward service/adguard-home-ui 3000:3000
```

Open `http://localhost:3000` and sign in as `admin` with the password supplied
to the helper. The password hash, live configuration, query log, and filter
data are stored only in Kubernetes or on retained Longhorn volumes.

## Router cutover

After direct DNS queries succeed, advertise `192.168.187.210` as the only LAN
DNS server through the router's DHCP configuration. Do not advertise a public
secondary resolver because clients may use it during normal operation and
bypass filtering. Configure IPv6 RDNSS consistently or devices may bypass the
IPv4 DNS server.

Renew a client's DHCP lease and verify both direct and DHCP-provided DNS:

```sh
dig @192.168.187.210 example.com
dig @192.168.187.210 ad.ae.doubleclick.net
dig adservice.google.com
```

The first query should resolve normally. After the HaGeZi list is loaded, the
advertising-domain query should be blocked and visible in AdGuard Home's query
log.

## Availability

The StatefulSet runs one writable AdGuard Home instance because AdGuard Home
does not provide native shared configuration or query-log clustering. Longhorn
replicates the persistent volumes across nodes, but a complete Kubernetes
outage will also make this DNS address unavailable. Use a second independent,
identically configured DNS server outside this cluster if full-cluster outage
coverage is required.
