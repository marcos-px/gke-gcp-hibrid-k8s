#!/bin/bash
set -euo pipefail

ENVIRONMENT=${1:-develop}
IMAGE_TAG=${2:-latest}
CLUSTER_NAME=${3:-lab-k8s-cluster-dev}
REGION=${4:-southamerica-east1}
PROJECT_ID=${5:-lab-k8s-svc-dev}

gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region "$REGION" \
  --project "$PROJECT_ID"

cd overlays/"$ENVIRONMENT"

kustomize edit set image \
  "REGION-docker.pkg.dev/PROJECT_ID/app-images/hybrid-api=southamerica-east1-docker.pkg.dev/${PROJECT_ID}/app-images/hybrid-api:${IMAGE_TAG}"

kubectl apply -k .

kubectl rollout status deployment/hybrid-api -n app --timeout=300s

echo "Deploy ok — ${ENVIRONMENT} @ ${IMAGE_TAG}"