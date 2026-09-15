#!/usr/bin/env python3
"""Push locally built Loky images using a temporary, restricted cluster Pod."""

import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
CRANE_IMAGE = "gcr.io/go-containerregistry/crane:debug@sha256:e78770b31258a3846f878036d9c1f63fbe4c871f9f56990bf77fd95c013e3c1b"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-image", default="loky-server:latest")
    parser.add_argument("--web-image", default="loky-web:latest")
    parser.add_argument("--tag", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", args.tag):
        parser.error("Invalid image tag.")
    os.umask(0o077)
    kube = ["kubectl", "--kubeconfig", os.environ.get("KUBECONFIG", str(ROOT / ".local/kubeconfig")), "-n", "registry"]
    credentials = dict(shlex.split(line)[0].split("=", 1)
                       for line in (ROOT / ".local/registry.env").read_text().splitlines() if line.strip())
    basic = base64.b64encode(f"{credentials['REGISTRY_PUSH_USERNAME']}:{credentials['REGISTRY_PUSH_PASSWORD']}".encode()).decode()
    name = f"loky-push-{secrets.token_hex(4)}"
    documents = [
        {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": name, "namespace": "registry"},
         "data": {"ca.crt": (ROOT / "talos/registry-ca.crt").read_text()}},
        {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": name, "namespace": "registry"},
         "type": "kubernetes.io/dockerconfigjson", "stringData": {
             ".dockerconfigjson": json.dumps({"auths": {"registry.homelab.internal": {"auth": basic}}})}},
        {"apiVersion": "v1", "kind": "Pod", "metadata": {"name": name, "namespace": "registry"}, "spec": {
            "restartPolicy": "Never", "automountServiceAccountToken": False,
            "hostAliases": [{"ip": "192.168.187.211", "hostnames": ["registry.homelab.internal"]}],
            "securityContext": {"runAsNonRoot": True, "runAsUser": 1000, "runAsGroup": 1000,
                                "fsGroup": 1000, "seccompProfile": {"type": "RuntimeDefault"}},
            "containers": [{"name": "crane", "image": CRANE_IMAGE, "command": ["/busybox/sleep", "3600"],
                "env": [{"name": "DOCKER_CONFIG", "value": "/auth"}, {"name": "SSL_CERT_FILE", "value": "/ca/ca.crt"}],
                "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                                    "capabilities": {"drop": ["ALL"]}},
                "resources": {"requests": {"cpu": "250m", "memory": "256Mi"}, "limits": {"cpu": "2", "memory": "1Gi"}},
                "volumeMounts": [{"name": "work", "mountPath": "/work"}, {"name": "ca", "mountPath": "/ca", "readOnly": True},
                                 {"name": "auth", "mountPath": "/auth", "readOnly": True}]}],
            "volumes": [{"name": "work", "emptyDir": {"sizeLimit": "2Gi"}},
                        {"name": "ca", "configMap": {"name": name}},
                        {"name": "auth", "secret": {"secretName": name,
                            "items": [{"key": ".dockerconfigjson", "path": "config.json"}]}}]}}
    ]
    pins = {}
    try:
        for document in documents:
            subprocess.run([*kube, "create", "-f", "-"], input=json.dumps(document), text=True, check=True)
        subprocess.run([*kube, "wait", "--for=condition=Ready", f"pod/{name}", "--timeout=45s"], check=True)
        with tempfile.TemporaryDirectory(prefix="loky-images-", dir=ROOT / ".local") as directory:
            for component, local_image in [("server", args.server_image), ("web", args.web_image)]:
                architecture = subprocess.check_output(["docker", "image", "inspect", "--format", "{{.Architecture}}", local_image], text=True).strip()
                if architecture != "amd64":
                    raise SystemExit("Build images with --platform linux/amd64 before pushing.")
                archive = str(Path(directory) / f"{component}.tar")
                subprocess.run(["docker", "image", "save", "-o", archive, local_image], check=True)
                subprocess.run([*kube, "cp", archive, f"{name}:/work/{component}.tar"], check=True)
                remote = f"registry.homelab.internal/loky/{component}:{args.tag}"
                subprocess.run([*kube, "exec", name, "--", "/ko-app/crane", "push", f"/work/{component}.tar", remote], check=True)
                digest = subprocess.check_output([*kube, "exec", name, "--", "/ko-app/crane", "digest", remote], text=True).strip()
                if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
                    raise SystemExit("Registry returned an invalid image digest.")
                pins[component] = f"{remote}@{digest}"
        manifest = ROOT / "applications/loky-planner/deployments.yaml"
        content = manifest.read_text()
        for component, image in pins.items():
            content = re.sub(rf"image: registry\.homelab\.internal/loky/{component}:[^\s]+", f"image: {image}", content)
        manifest.write_text(content)
        print("Updated Loky deployment manifests with verified image digests. Commit and push the change for Argo CD.")
    finally:
        subprocess.run([*kube, "delete", "pod,secret,configmap", name, "--ignore-not-found", "--wait=false"], check=False)


if __name__ == "__main__":
    main()
