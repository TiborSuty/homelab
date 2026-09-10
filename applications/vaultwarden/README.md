# Vaultwarden

Vaultwarden provides a private Bitwarden-compatible password vault at:

- <https://vaultwarden.vaultwarden.homelab.internal>

The hostname is available only through the private NetBird network resource.
NGINX terminates TLS with a cert-manager-managed internal CA before forwarding
to Vaultwarden on the Pod loopback network. The service is not published
through the public NetBird Cloud reverse proxy because native Bitwarden clients
must reach Vaultwarden directly without dashboard bearer authentication.

The single Vaultwarden replica stores its SQLite database and attachments on a
retained 2 GiB Longhorn volume. Longhorn replication is not an off-cluster
backup. Back up the complete `/data` directory to independent storage and test
restoration before treating the vault as the only copy of a credential.

## First account

`SIGNUPS_ALLOWED` is temporarily `true` for first-account registration. Access
is restricted by the NetBird `dashboard-access` policy while this is enabled.
Immediately after creating the first account, change the value to `false`,
commit, and let Argo CD reconcile the StatefulSet.

Keep the master password, two-factor recovery code, and a copy of the internal
CA recovery material outside Vaultwarden so a cluster loss cannot lock out the
operator.

## Client setup

Run the repository helper on macOS after Argo CD reports Vaultwarden healthy:

```sh
./bootstrap/configure-vaultwarden-client.sh
```

The helper installs the Bitwarden CLI through Homebrew when needed, trusts only
the generated Vaultwarden CA in the user's login keychain, and configures `bw`
for the private server. It does not log in, unlock the vault, or persist a
master password or session key.
