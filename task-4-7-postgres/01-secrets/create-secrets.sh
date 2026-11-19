#!/usr/bin/env bash
# Creates the Kubernetes secrets for task 4.7 from environment variables,
# so no credential is ever written to a file in this repository.
#
# Usage:
#   read -rs APP_DB_PASSWORD && export APP_DB_PASSWORD
#   read -rs S3_ACCESS_KEY_ID && export S3_ACCESS_KEY_ID
#   read -rs S3_SECRET_ACCESS_KEY && export S3_SECRET_ACCESS_KEY
#   ./01-secrets/create-secrets.sh

set -euo pipefail

NAMESPACE="${NAMESPACE:-aswin-kl}"

: "${APP_DB_PASSWORD:?APP_DB_PASSWORD is not set}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is not set}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is not set}"
: "${S3_REGION:?S3_REGION is not set}"
# Application user. CNPG requires type kubernetes.io/basic-auth with
# keys "username" and "password". The username must match the initdb owner.
kubectl create secret generic task-4-7-aswin-app-user \
  --namespace "$NAMESPACE" \
  --type kubernetes.io/basic-auth \
  --from-literal=username=app \
  --from-literal=password="$APP_DB_PASSWORD" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - \
      app.kubernetes.io/name=task-4-7-aswin-pg \
      cnpg.io/reload=true \
      -o yaml \
  | kubectl apply -f -

# Civo Object Storage credentials, read by the Barman Cloud plugin.
kubectl create secret generic task-4-7-aswin-s3-creds \
  --namespace "$NAMESPACE" \
  --from-literal=ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  --from-literal=ACCESS_SECRET_KEY="$S3_SECRET_ACCESS_KEY" \
  --from-literal=REGION="$S3_REGION" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - \
      app.kubernetes.io/name=task-4-7-aswin-pg \
      cnpg.io/reload=true \
      -o yaml \
  | kubectl apply -f -

kubectl get secret -n "$NAMESPACE" task-4-7-aswin-app-user task-4-7-aswin-s3-creds
