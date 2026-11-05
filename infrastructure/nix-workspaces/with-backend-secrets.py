#!/usr/bin/env python3
"""Run a non-interactive fullstack backend command using Mac Vaultwarden tokens.

Usage: with_dev_secrets python3 with-backend-secrets.py bin/ai-mono project dms doctor
The existing Mac helper owns vault unlocking/locking. This transport never writes
tokens to files or command arguments. The invoked command controls their use;
Compose may retain COMPOSER_AUTH in its Composer container's configuration.
"""

import os
import shlex
import subprocess
import sys


TOKEN_NAMES = (
    "CARVAGO_GITHUB_ACCESS_TOKEN",
    "CARVAGO_GITLAB_ACCESS_TOKEN",
)


def command_script(command, environment):
    missing = [name for name in TOKEN_NAMES if not environment.get(name)]
    if missing:
        raise ValueError("Missing " + ", ".join(missing) + "; run through with_dev_secrets on your Mac.")
    lines = ["set +x +v", "set -eu", "ulimit -c 0", "unset HISTFILE"]
    for name in TOKEN_NAMES:
        value = environment[name]
        if "\x00" in value:
            raise ValueError("Invalid value for " + name)
        lines.append("export " + name + "=" + shlex.quote(value))
    lines.append('cd "$HOME/projects/backend-monorepo"')
    lines.append("exec " + shlex.join(command) + " </dev/null")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) < 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    try:
        script = command_script(sys.argv[1:], os.environ)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    # Only the encrypted stdin stream carries tokens. The ssh client, its
    # arguments, and any ProxyCommand do not need the secret environment.
    ssh_environment = {
        key: value for key, value in os.environ.items()
        if key not in (*TOKEN_NAMES, "BW_SESSION")
    }
    result = subprocess.run(
        ["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
         "fullstack", "exec env -u BASH_ENV -u ENV /opt/tools/bin/bash --noprofile --norc -s"],
        input=script.encode(), env=ssh_environment,
    )
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == "__main__":
    sys.exit(main())
