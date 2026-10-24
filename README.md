# Apex

A small blogging app deployed to Google Cloud with a fully automated, infrastructure-as-code pipeline.

- [App](#app): what the application is and how to run it locally
- [Infrastructure](#infrastructure): how it's hosted, built, deployed and monitored

For the deeper operational details (resource-by-resource breakdown, design decisions, known gaps), see [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## App

Users sign up, write posts, browse a feed of everyone's posts, and manage their profile.

| Layer | Tech |
|---|---|
| Frontend | React + Vite, built to static files and served by nginx |
| Backend | Node.js (Express) REST API under `/api`, Sequelize ORM, Umzug migrations |
| Database | PostgreSQL |
| Auth | JWT access + refresh tokens, bcrypt, rate limiting |
| Telemetry | `prom-client` metrics on a separate internal port (`9091`), structured logs via `pino` |

### Run locally

Requires Docker and Docker Compose.

```bash
cp .env.example .env                          # fill in the secrets
docker compose up --build
docker compose exec backend npm run migrate   # DB starts empty
```

Frontend on `http://localhost`, API on `http://localhost:5001/api`.

### Tests

```bash
cd backend  && npm test         # integration tests, need a Postgres (see ci.yaml for the env vars)
cd frontend && npm run test:ci
```

---

## Infrastructure

### At a glance

```
                      GitHub Actions
          ┌──────────────┼──────────────────┐
          │ CI           │ CD (main only)   │
          │ test & lint  │ terraform apply  │ docker push ──▶ Docker Hub
          │              │ helm upgrade     │                    │ pull
          ▼              ▼                  ▼                    ▼
                 GCP project (us-central1)
   ┌─────────────────────────────────────────────────────────────┐
   │  VPC                                                        │
   │   ├─ Cloud SQL (Postgres 15, private IP only, backups+PITR) │
   │   │        ▲ private peering                                │
   │   └─ GKE cluster ── 1 Spot node pool (autoscale 1–5)        │
   │        ├─ ns apex-app:        ingress-nginx, frontend,      │
   │        │                      backend, migration Job        │
   │        └─ ns apex-monitoring: Prometheus, Grafana, Loki     │
   └─────────────────────────────────────────────────────────────┘
                 ▲
     static IP ──┘  http://<ip>/       → frontend
                    http://<ip>/api    → backend
                    http://<ip>/grafana → Grafana
```

One static IP and one ingress controller front everything. The database is never exposed publicly; only pods inside the VPC can reach it.

### Tools and why

| Tool | Used for | Why |
|---|---|---|
| **Google Cloud (GKE, Cloud SQL, VPC)** | Hosting | Managed Kubernetes and a managed Postgres with backups and point-in-time recovery, so we don't operate a database ourselves |
| **Terraform** | Everything long-lived: network, static IP, Cloud SQL, GKE cluster, namespaces, secrets, ingress controller | Infrastructure is reviewable code; remote state in a GCS bucket means CI and local runs see the same state |
| **Helm** | Deploying the app to Kubernetes | Templated manifests, one command to deploy, and built-in `--wait` + automatic rollback when a release doesn't become healthy |
| **Docker + Docker Hub** | Building and storing images | Public HTTPS registry nodes trust out of the box. An in-cluster registry was tried first and caused more problems than it solved (see ARCHITECTURE.md) |
| **ingress-nginx** | Single public entry point, path-based routing | One IP for the app, API and Grafana; no per-service load balancers |
| **kube-prometheus-stack** | Metrics, dashboards, alerting (Prometheus, Grafana, Alertmanager) | Standard Kubernetes monitoring bundle; the app's metrics are picked up automatically through a `ServiceMonitor` |
| **Loki + Promtail** | Log collection, queried from Grafana | Logs and metrics in one UI |
| **GitHub Actions** | CI and CD | Lives next to the code; no separate CI server to run |

### What Terraform owns vs what Helm deploys

The split follows how often things change:

- **Terraform (rarely changes):** the VPC, Cloud SQL, the GKE cluster, the static IP, namespaces, Kubernetes Secrets/ConfigMaps (DB credentials, JWT secrets, Docker Hub pull secret), and the ingress-nginx controller bound to the static IP.
- **Helm in CD (changes every deploy):** the monitoring stack, the Grafana ingress, and the app chart (frontend, backend, migration Job, app ingress, ServiceMonitor).

Secrets flow one way: **GitHub secrets → Terraform variables → Kubernetes Secrets**, and the Helm charts only reference them by name. No credentials live in the repo.

### How a change gets to production

**CI (`ci.yaml`) runs on every push to any branch:**
- **Backend:** migrations + integration tests against a real Postgres container
- **Frontend:** build + tests
- **Infra:** `terraform fmt`/`validate` and `helm lint`, without touching real infrastructure

**CD (`cd.yaml`) runs only when CI passes on `main`:**

1. **Terraform:** `plan`, then `apply` exactly that plan. This brings the infrastructure in line with the code and outputs the static IP.
2. **Docker:** builds and pushes backend and frontend images, tagged with the commit SHA.
3. **Kubernetes:**
   - updates the monitoring stack
   - deploys the app chart, which first runs DB migrations as a pre-deploy Job
   - rolls out the new images, waits until pods are healthy, and rolls back automatically if they aren't
   - finishes with a smoke test against the public IP

Key properties:
- **Deploys exactly what was tested.** Every CD job checks out the commit CI tested, not whatever is newest on `main`.
- **Every deploy is traceable and reversible.** Each one gets a new image tag, so `helm rollback` returns to the exact previous version.
- **Migrations gate the rollout.** If they fail, the new version never starts.
- **One deploy at a time.** Overlapping runs queue instead of racing on Terraform state or Helm releases.

**Destroy (`destroy.yaml`):** manual, guarded by typing `destroy`. It tears down only the cluster. The database (deletion-protected) and its network stay, so the next CD run rebuilds the cluster with the data intact.

### Observability

- **Metrics:** Prometheus scrapes cluster metrics plus the backend's own request and DB-latency metrics.
- **Logs:** Promtail ships all container logs to Loki.
- **Grafana** shows both, at `http://<ingress-ip>/grafana`.

### Repository layout

```
backend/            Express API, migrations, Dockerfile
frontend/           React app, nginx config, Dockerfile
terraform/          root config + modules: network, sql, cluster, helm_app, helm_monitoring
k8s/apex-app/       Helm chart: frontend, backend, migration Job, ingress, ServiceMonitor
k8s/apex-monitoring/ Helm chart: Grafana ingress
.github/workflows/  ci.yaml, cd.yaml, destroy.yaml
docker-compose.yaml local development
```

### Required GitHub secrets

| Secret | Purpose |
|---|---|
| `GCP_SA_KEY` | Service account key Terraform/Helm use to access GCP |
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | Push images in CD; pull secret for the cluster |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `SALT` | Backend auth settings, passed through Terraform into Kubernetes Secrets |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin login |

### Known trade-offs

Spot nodes keep costs low but can be reclaimed at any time. There's no HTTPS yet, because that needs a domain first. Prometheus and Loki keep their data on node-local storage, so it's lost when a node is reclaimed. ARCHITECTURE.md §8 has the full list.
