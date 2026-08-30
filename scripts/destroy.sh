#!/usr/bin/env bash
set -e
echo "=== Destroying Kubernetes & AWS Infrastructure ==="
kubectl delete namespace number-reverser --ignore-not-found=true || true

cd terraform
terraform destroy -auto-approve
echo "Teardown complete! Zero residual AWS cloud spend."
