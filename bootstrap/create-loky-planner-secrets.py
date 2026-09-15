#!/usr/bin/env python3
"""Create Loky's private credentials without printing or committing values."""

import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess


ROOT = Path(__file__).resolve().parent.parent
KUBECONFIG = os.environ.get("KUBECONFIG", str(ROOT / ".local/kubeconfig"))
CREDENTIALS = ROOT / ".local/loky-planner.env"


def kubectl(*arguments, document=None, optional=False):
    result = subprocess.run(
        ["kubectl", "--kubeconfig", KUBECONFIG, *arguments],
        input=json.dumps(document) if document is not None else None,
        capture_output=True,
        text=True,
    )
    if result.returncode and not optional:
        raise SystemExit("Kubernetes credential provisioning failed; values were withheld.")
    return result


def apply_secret(namespace, name, values, secret_type="Opaque"):
    kubectl("apply", "-f", "-", document={
        "apiVersion": "v1", "kind": "Secret",
        "metadata": {"name": name, "namespace": namespace},
        "type": secret_type, "stringData": values,
    })
    print(f"Provisioned Secret {namespace}/{name}.")


def main():
    os.umask(0o077)
    if not Path(KUBECONFIG).is_file():
        raise SystemExit("Kubeconfig not found.")
    kubectl("apply", "-f", "-", document={
        "apiVersion": "v1", "kind": "Namespace",
        "metadata": {"name": "loky-planner", "labels": {
            f"pod-security.kubernetes.io/{mode}": "restricted"
            for mode in ("enforce", "audit", "warn")
        }},
    })
    if CREDENTIALS.exists():
        values = dict(shlex.split(line)[0].split("=", 1)
                      for line in CREDENTIALS.read_text().splitlines() if line.strip())
    else:
        existing = kubectl("-n", "loky-planner", "get", "secret", "loky-runtime", "-o", "json", optional=True)
        if existing.returncode == 0:
            raise SystemExit("Existing Loky credentials found. Restore the local credential file before rerunning.")
        values = {
            "PG_PASSWORD": secrets.token_hex(24),
            "REDIS_PASSWORD": secrets.token_hex(24),
            "S3_ACCESS_KEY_ID": "loky-planner",
            "S3_SECRET_ACCESS_KEY": secrets.token_hex(24),
            "S3_BUCKET": "loky-media",
        }
        values["DATABASE_URL"] = f"postgres://loky:{values['PG_PASSWORD']}@loky-postgres-rw.loky-planner.svc.cluster.local:5432/loky"
        values["REDIS_URL"] = f"redis://:{values['REDIS_PASSWORD']}@loky-redis.loky-planner.svc.cluster.local:6379"
        CREDENTIALS.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with CREDENTIALS.open("x") as file:
            file.write("".join(f"{key}={shlex.quote(value)}\n" for key, value in values.items()))
    CREDENTIALS.chmod(0o600)
    apply_secret("loky-planner", "loky-postgres-credentials", {
        "username": "loky", "password": values["PG_PASSWORD"],
    }, "kubernetes.io/basic-auth")
    apply_secret("loky-planner", "loky-runtime", {
        key: values[key] for key in ("DATABASE_URL", "REDIS_URL", "REDIS_PASSWORD", "S3_ACCESS_KEY_ID", "S3_SECRET_ACCESS_KEY")
    })
    apply_secret("minio", "loky-planner-storage-credentials", {
        key: values[key] for key in ("S3_ACCESS_KEY_ID", "S3_SECRET_ACCESS_KEY", "S3_BUCKET")
    })
    original = json.loads(kubectl("-n", "registry", "get", "secret", "registry-pull", "-o", "json").stdout)
    kubectl("apply", "-f", "-", document={
        "apiVersion": "v1", "kind": "Secret",
        "metadata": {"name": "registry-pull", "namespace": "loky-planner"},
        "type": original["type"], "data": original["data"],
    })
    print("Provisioned Secret loky-planner/registry-pull.")
    print(f"Private credentials retained in {CREDENTIALS} (mode 600).")


if __name__ == "__main__":
    main()
