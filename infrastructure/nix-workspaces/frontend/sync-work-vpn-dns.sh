#!/bin/sh
set -eu

case "${1:-}" in
  ''|--once) ;;
  *) printf 'Usage: %s [--once]\n' "$0" >&2; exit 2 ;;
esac

# NetBird rewrites its own resolv.conf after login, logout, or peer renumbering.
# Publish only resolver addresses; never read or copy the peer identity files.
source_file=${WORK_VPN_RESOLV_CONF:-/etc/resolv.conf}
output_file=${WORK_VPN_DNS_OUTPUT:-/resolver/forward.conf}
cluster_dns=${CLUSTER_DNS_IP:-10.96.0.10}

sync_resolvers() {
  awk -v fallback="$cluster_dns" -v self="${POD_IP:-}" '
    BEGIN { printf "forward ." }
    $1 == "nameserver" && $2 ~ /^[0-9a-fA-F:.]+$/ &&
      $2 != fallback && $2 != self && !seen[$2]++ && count < 3 {
        printf " %s", $2
        count++
      }
    END {
      printf " %s {\n", fallback
      print "    policy sequential"
      print "    failover SERVFAIL REFUSED"
      print "    max_fails 1"
      print "    health_check 2s"
      print "}"
    }
  ' "$source_file" > "$output_file.tmp"
  chmod 0644 "$output_file.tmp"
  if cmp -s "$output_file.tmp" "$output_file"; then
    rm -f "$output_file.tmp"
  else
    mv "$output_file.tmp" "$output_file"
  fi
}

sync_resolvers
[ "${1:-}" != --once ] || exit 0
while sleep 2; do
  sync_resolvers
done
