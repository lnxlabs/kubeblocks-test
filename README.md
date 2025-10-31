# 🚀 KubeBlocks Test Setup

Dieses Repository enthält eine vollständige Installation von **KubeBlocks** inklusive der Addons **Redis** und **RabbitMQ**.
Das Setup ist optimiert für lokale Testumgebungen (z. B. Docker Desktop oder k3s) und bietet **zwei Deployment-Varianten**:

1. **ArgoCD-gesteuert** (GitOps-Ansatz)
2. **Helmfile-basiert** (direktes Helm-Deployment)

---

## 📦 Struktur

```
.
├── apps/                         # ArgoCD Applications (GitOps)
│   ├── kubeblocks.yaml
│   ├── redis.yaml
│   ├── redis-cluster.yaml
│   ├── rabbitmq.yaml
│   ├── rabbitmq-cluster.yaml
│   └── root-app.yaml
├── helmfile/                     # Helmfile-basiertes Setup
│   ├── helmfile.yaml
│   └── install.sh
├── manifests/                    # Gemeinsame Clusterdefinitionen
│   ├── redis/
│   │   └── cluster.yaml
│   └── rabbitmq/
│       └── cluster.yaml
├── test-kubeblocks-argocd.sh     # Test-Skript für ArgoCD
├── test-kubeblocks-helmfile.sh   # Test-Skript für Helmfile
└── README.md
```

---

## ⚙️ Voraussetzungen

### Für beide Varianten:
- Kubernetes ≥ 1.26 (z. B. Docker Desktop, k3s oder minikube)
- Helm ≥ 3.10
- `kubectl` CLI installiert
- Internetzugang zu Helm-Repos von [apecloud](https://apecloud.github.io/helm-charts)

### Zusätzlich für ArgoCD-Variante:
- Argo CD ≥ 2.8
- `argocd` CLI installiert

### Zusätzlich für Helmfile-Variante:
- Helmfile installiert ([Installation](https://helmfile.readthedocs.io/en/latest/#installation))

---

## 🚀 Installation

Du kannst zwischen zwei Deployment-Ansätzen wählen:

<details>
<summary><b>Option A: Installation via ArgoCD (GitOps)</b></summary>

### 1️⃣ Namespace und ArgoCD bereitstellen

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --set server.service.type=LoadBalancer
```

> 💡 Zugriff auf das UI:
> ```bash
> kubectl port-forward svc/argocd-server -n argocd 8080:443
> ```
> Dann im Browser: [https://localhost:8080](https://localhost:8080)

### 2️⃣ KubeBlocks-CRDs manuell installieren

Bevor ArgoCD den Operator deployen kann, **müssen die CRDs manuell installiert werden**:

```bash
kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v1.0.1/kubeblocks_crds.yaml
```

> 📘 Hinweis:
> Diese CRDs definieren die benutzerdefinierten Ressourcen (`Cluster`, `ClusterDefinition`, `Component`, etc.),
> die KubeBlocks zur Verwaltung von Datenbank-Clustern verwendet.

### 3️⃣ Root-App deployen (ArgoCD Bootstrap)

```bash
kubectl apply -f apps/root-app.yaml -n argocd
```

ArgoCD erstellt automatisch alle abhängigen Apps:
- `kubeblocks` (Core Operator)
- `redis-addon` und `rabbitmq-addon`
- `redis-cluster` und `rabbitmq-cluster`

### 4️⃣ Testen

```bash
./test-kubeblocks-argocd.sh
```

</details>

<details open>
<summary><b>Option B: Installation via Helmfile</b></summary>

### 1️⃣ Installation ausführen

Das Installations-Skript führt alle notwendigen Schritte automatisch aus:

```bash
cd helmfile
./install.sh
```

Das Skript führt folgende Schritte aus:
1. ✅ Prüft Prerequisites (kubectl, helm, helmfile)
2. 📦 Installiert KubeBlocks CRDs
3. 🚀 Deployed KubeBlocks Operator + Addons via Helmfile
4. ⏳ Wartet bis der Operator bereit ist
5. 🗄️ Deployed Redis & RabbitMQ Cluster aus `manifests/`

### 2️⃣ Testen

```bash
cd ..
./test-kubeblocks-helmfile.sh
```

### 3️⃣ Manuelles Sync (optional)

Falls du Änderungen am Helmfile vornimmst:

```bash
cd helmfile
helmfile sync
```

</details>

---

## 🧠 Namespaces

| Komponente        | Namespace           | Beschreibung |
|-------------------|---------------------|---------------|
| ArgoCD (optional) | `argocd`            | ArgoCD UI & Controller |
| KubeBlocks Core   | `kubeblocks-system` | Operator, CRDs, Addons |
| Datenbanken       | `data`              | Redis & RabbitMQ Cluster |

---

## 🧪 Test & Überprüfung

### Cluster-Status prüfen
```bash
kubectl get clusters.apps.kubeblocks.io -n data
```

Erwartet:
```
NAME                CLUSTER-DEFINITION   STATUS     AGE
redis-cluster       redis                Running    ...
rabbitmq-cluster    rabbitmq             Running    ...
```

### Pods überprüfen
```bash
kubectl get pods -n data
```

### Logs anzeigen
```bash
kubectl logs -n kubeblocks-system deploy/kubeblocks
```

---

## 🔁 Updaten & Synchronisieren

### ArgoCD-Variante
```bash
argocd app list -o name | xargs -n1 argocd app sync
```

### Helmfile-Variante
```bash
cd helmfile
helmfile sync
```

---

## 🧰 Debugging

### RabbitMQ oder Redis startet nicht?
```bash
kubectl describe cluster rabbitmq-cluster -n data
kubectl describe cluster redis-cluster -n data
kubectl get pods -n kubeblocks-system
kubectl logs deploy/kubeblocks -n kubeblocks-system | tail -n 50
```

### Helmfile-Status prüfen
```bash
cd helmfile
helmfile status
```

### VolumeSnapshot-Fehler (optional)
Falls KubeBlocks nach `VolumeSnapshot.snapshot.storage.k8s.io` verlangt:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
```

---

## 🧼 Entfernen

### ArgoCD-Variante
```bash
argocd app delete root -n argocd --cascade
kubectl delete namespace data kubeblocks-system argocd
```

### Helmfile-Variante
```bash
kubectl delete -f manifests/redis/cluster.yaml
kubectl delete -f manifests/rabbitmq/cluster.yaml
cd helmfile
helmfile destroy
kubectl delete namespace data kubeblocks-system
```

### CRDs entfernen (beide Varianten)
```bash
kubectl delete -f https://github.com/apecloud/kubeblocks/releases/download/v1.0.1/kubeblocks_crds.yaml
```

---

## 🧠 Hinweise

- `replicas: 1` und `storageClassName: hostpath` sind für lokale Umgebungen voreingestellt.
- In produktiven Clustern sollte eine Cloud-StorageClass (z. B. `gp2`, `managed-premium`, `csi-disk`) genutzt werden.
- Die `dataprotection`-Komponente von KubeBlocks ist deaktiviert (kein Snapshot-CRD erforderlich).
- Beide Varianten nutzen die gleichen Cluster-Manifests aus dem `manifests/` Verzeichnis.

---

## 💚 Autor

**Bastian Sommerer**
IT-Freelancer & DevOps-Engineer
👉 [lnxlabs](https://github.com/lnxlabs)
