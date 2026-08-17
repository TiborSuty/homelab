# Správa nodov s Argo CD

`kubectl` je vhodné používať na dočasné operácie. Pri Argo CD by trvalé
zmeny nemali existovať iba ako ručne vykonaný `kubectl` príkaz, pretože Git má
byť zdroj pravdy a Argo CD môže manuálnu zmenu označiť ako drift alebo ju pri
zapnutom `selfHeal` vrátiť. Viac informácií je v dokumentácii
[Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

## Odporúčané rozdelenie zodpovedností

| Oblasť | Nástroj |
| --- | --- |
| IP, hostname, disky, kernel a kubelet | Talos MachineConfig |
| Trvalé node labels dostupné Talosu | Talos per-node patch |
| Aplikácie, Cilium, Longhorn a monitoring | Argo CD |
| Kontrola stavu a diagnostika | `kubectl` |
| `cordon`, `drain` a `uncordon` počas údržby | `kubectl` |
| Núdzový manuálny zásah | `kubectl`, potom zmenu zapísať do Gitu |

Rozumné použitie `kubectl`:

```sh
kubectl get nodes
kubectl describe node controlplane-1
kubectl cordon controlplane-1
kubectl drain controlplane-1
kubectl uncordon controlplane-1
```

Menej vhodné ako trvalá konfigurácia:

```sh
kubectl label node controlplane-1 storage=longhorn
kubectl taint node controlplane-1 workload=database:NoSchedule
```

Takéto zmeny prežijú, ale nie sú zaznamenané v Gite. Neskôr preto nemusí byť
jasné, prečo ich node má.

Talos dokáže niektoré labels nastaviť cez `machine.nodeLabels`. Pri role labels
a taintoch však platia obmedzenia Kubernetes `NodeRestriction`; tainty po
registrácii musí meniť cluster-admin cez `kubectl` alebo samostatný controller.
Podrobnosti opisuje dokumentácia
[Talos node labels and taints](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/node-labels).

Technicky môže Argo CD dostať oprávnenie spravovať cluster-scoped objekty
`Node`, ale pre tento cluster to nie je odporúčané:

- Argo CD môže bojovať s kubeletom o dynamické polia nodu.
- `selfHeal` môže rušiť manuálne maintenance zásahy.
- Argo CD potrebuje veľmi silné cluster-wide oprávnenia.
- Pri nefunkčnom Kubernetes API alebo Argo CD nie je možné node týmto spôsobom
  opraviť.

Odporúčané pravidlo pre tento homelab:

```text
Talos patches = trvalá konfigurácia serverov
Argo CD       = trvalá konfigurácia Kubernetes
kubectl       = pozorovanie, údržba a núdzové zásahy
```
