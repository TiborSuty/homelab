#!/usr/bin/env zsh
# Mock-only security checks: never unlock or read a real vault.
setopt noxtrace
unset CARVAGO_GITHUB_ACCESS_TOKEN CARVAGO_GITLAB_ACCESS_TOKEN PHRASE_STRINGS_TOKEN BW_SESSION BW_PASSWORD BW_CLIENTID BW_CLIENTSECRET
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
export CHECK_DIR="$check_dir"
export VAULTWARDEN_CA_FILE="$check_dir/ca.crt"
: > "$VAULTWARDEN_CA_FILE"
mkdir "$check_dir/bin"
cat > "$check_dir/bin/bw" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$1" >> "$CHECK_DIR/calls"
case "$1" in
  unlock)
    test "$CHECK_MODE" != unlock-fail || exit 3
    test "$CHECK_MODE" != empty-session || exit 0
    printf 'mock-session\n' ;;
  sync)
    test "${BW_SESSION:-}" = mock-session
    test "$CHECK_MODE" != sync-fail ;;
  get)
    test "${BW_SESSION:-}" = mock-session
    case "$3" in
      dev/carvago/github-access-token)
        test "$CHECK_MODE" != github-fail || exit 4
        printf 'mock-github-token\n' ;;
      dev/carvago/gitlab-access-token)
        test "$CHECK_MODE" != empty-gitlab || exit 0
        printf 'mock-gitlab-token\n' ;;
      *) exit 5 ;;
    esac ;;
  lock) test -z "${BW_SESSION:-}" ;;
  *) exit 6 ;;
esac
MOCK
cat > "$check_dir/child" <<'MOCK'
#!/bin/sh
set -eu
test "$CARVAGO_GITHUB_ACCESS_TOKEN" = mock-github-token
test "$CARVAGO_GITLAB_ACCESS_TOKEN" = mock-gitlab-token
test -z "${BW_SESSION:-}${PHRASE_STRINGS_TOKEN:-}${BW_PASSWORD:-}"
touch "$CHECK_DIR/child-ran"
exit 23
MOCK
chmod 700 "$check_dir/bin/bw" "$check_dir/child"
export PATH="$check_dir/bin:$PATH"
source "${1:-/opt/dotfiles/nix/home/vaultwarden.zsh}"
for mode in success unlock-fail empty-session sync-fail github-fail empty-gitlab; do
  export CHECK_MODE="$mode"
  : > "$check_dir/calls"
  rm -f "$check_dir/child-ran"
  with_dev_secrets "$check_dir/child" > "$check_dir/output" 2>&1
  result=$?
  if [[ "$mode" == success ]]; then
    [[ "$result" == 23 && -f "$check_dir/child-ran" ]] || exit 1
  else
    [[ "$result" != 0 && ! -e "$check_dir/child-ran" ]] || exit 1
  fi
  [[ "$(tail -n 1 "$check_dir/calls")" == lock ]] || exit 1
  [[ -z "${CARVAGO_GITHUB_ACCESS_TOKEN:-}${CARVAGO_GITLAB_ACCESS_TOKEN:-}${BW_SESSION:-}${PHRASE_STRINGS_TOKEN:-}" ]] || exit 1
  if grep -Eq 'mock-(github-token|gitlab-token|session)' "$check_dir/output"; then
    print -u2 'FAIL: credential leaked into output'
    exit 1
  fi
  print "PASS: $mode; cleanup, exit status, and command-only credentials"
done
