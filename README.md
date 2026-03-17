# gke-gcp-hybrid-k8s

Manifests Kubernetes para deploy da **hybrid-api** no **Google Kubernetes Engine (GKE)**, organizados com [Kustomize](https://kustomize.io/) e estruturados com base/overlays por ambiente.

---

## Estrutura do Repositório

```
.
├── base/                        # Manifests base (compartilhados entre todos os ambientes)
│   ├── configmap.yaml           # Variáveis de configuração da aplicação
│   ├── deployment.yaml          # Deployment da hybrid-api + Cloud SQL Proxy sidecar
│   ├── hpa.yml                  # HorizontalPodAutoscaler (min 2 / max 10 réplicas)
│   ├── namespace.yml            # Namespace: app
│   ├── networkpolicy.yaml       # NetworkPolicies (deny-all + ingress/egress explícitos)
│   ├── poddisruptionbudget.yaml # PodDisruptionBudget para high availability
│   ├── secret.yaml              # Secret (app-secrets) para credenciais DB
│   ├── service.yaml             # Service ClusterIP na porta 80
│   └── serviceaccount.yaml      # ServiceAccount (app-ksa) com Workload Identity
│
├── overlays/
│   ├── develop/                 # Configurações específicas para develop
│   │   └── kustomization.yaml   # 2 réplicas, image tag: latest
│   └── production/              # Configurações específicas para production
│       └── kustomization.yaml   # 4 réplicas, recursos aumentados (CPU/Memory)
│
└── scripts/
    └── deploy.sh                # Script de deploy via gcloud + kustomize + kubectl
```

---

## Arquitetura

A aplicação roda no GKE com os seguintes componentes por pod:

| Container        | Imagem                                        | Função                          |
|------------------|-----------------------------------------------|---------------------------------|
| `api`            | `southamerica-east1-docker.pkg.dev/.../hybrid-api` | Aplicação principal (porta 8080) |
| `cloud-sql-proxy`| `gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0` | Proxy para Cloud SQL via Private IP |

### Segurança

- **Workload Identity** via `ServiceAccount` (`app-ksa`)
- Containers rodam como **non-root** (`runAsUser: 1000`)
- `readOnlyRootFilesystem: true` e `allowPrivilegeEscalation: false`
- **NetworkPolicy**: deny-all por padrão, com liberações explícitas:
  - Ingress: aceita tráfego apenas do namespace `ingress-nginx` na porta 8080
  - Egress: DNS (53/UDP+TCP), Cloud SQL Proxy local (5432) e HTTPS externo (443)

### Alta Disponibilidade

- **PodAntiAffinity** para distribuição entre nodes
- **TopologySpreadConstraints** para distribuição entre zonas
- **HPA**: escala entre 2–10 réplicas com base em CPU (70%) e Memory (80%)
- **PodDisruptionBudget** para proteção durante manutenções
- **RollingUpdate** com `maxUnavailable: 0`

---

## Configuração

### ConfigMap (`app-config`)

| Chave               | Valor padrão                             |
|---------------------|------------------------------------------|
| `APP_ENV`           | `develop`                                |
| `APP_PORT`          | `8080`                                   |
| `LOG_LEVEL`         | `info`                                   |
| `DB_HOST`           | `127.0.0.1` (via Cloud SQL Proxy)        |
| `DB_PORT`           | `5432`                                   |
| `CLOUD_SQL_INSTANCE`| `PROJECT_ID:REGION:INSTANCE_NAME`        |

### Secret (`app-secrets`)

| Chave         | Descrição                    |
|---------------|------------------------------|
| `DB_NAME`     | Nome do banco de dados       |
| `DB_USER`     | Usuário do banco de dados    |
| `DB_PASSWORD` | Senha do banco de dados      |

> O `secret.yaml` não deve conter valores reais em repositório. Use o [Secret Manager](https://cloud.google.com/secret-manager) ou injete via CI/CD.

---

## Ambientes (Overlays)

| Parâmetro             | develop         | production      |
|-----------------------|-----------------|-----------------|
| Réplicas              | 2               | 4               |
| CPU request           | 100m            | 200m            |
| CPU limit             | 500m            | 1000m           |
| Memory request        | 128Mi           | 256Mi           |
| Memory limit          | 256Mi           | 512Mi           |

---

## Deploy

### Pré-requisitos

- [`gcloud`](https://cloud.google.com/sdk) configurado
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) instalado
- [`kustomize`](https://kustomize.io/) instalado

### Via script

```bash
# Sintaxe
./scripts/deploy.sh [ENVIRONMENT] [IMAGE_TAG] [CLUSTER_NAME] [REGION] [PROJECT_ID]

# Develop (padrões)
./scripts/deploy.sh

# Production com tag específica
./scripts/deploy.sh production v1.2.3 lab-k8s-cluster-prod southamerica-east1 meu-projeto-prod
```

### Via kubectl/kustomize manual

```bash
# Autenticar no cluster
gcloud container clusters get-credentials lab-k8s-cluster-dev \
  --region southamerica-east1 \
  --project lab-k8s-svc-dev

# Aplicar overlay de develop
kubectl apply -k overlays/develop

# Aplicar overlay de production
kubectl apply -k overlays/production

# Verificar rollout
kubectl rollout status deployment/hybrid-api -n app --timeout=300s
```

---

## Health Checks

| Tipo            | Endpoint  | Delay inicial | Período |
|-----------------|-----------|---------------|---------|
| `livenessProbe` | `/health` | 15s           | 20s     |
| `readinessProbe`| `/ready`  | 5s            | 10s     |
| `startupProbe`  | `/health` | 5s            | 5s (x12)|

---

## Imagem Docker

A imagem é publicada no **Artifact Registry**:

```
southamerica-east1-docker.pkg.dev/PROJECT_ID/app-images/hybrid-api:<TAG>
```

Substitua `PROJECT_ID` pelo ID do projeto GCP e `<TAG>` pela versão desejada.
