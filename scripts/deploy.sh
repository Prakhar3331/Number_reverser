#!/usr/bin/env bash
set -e
echo "=== 1. Provisioning AWS Infrastructure with Terraform ==="
cd terraform
terraform init
terraform apply -auto-approve
CLUSTER_NAME=$(terraform output -raw cluster_name)
ECR_URL=$(terraform output -raw ecr_repository_url)
cd ..

echo "=== 2. Updating Kubeconfig ==="
aws eks update-kubeconfig --region ap-south-1 --name "${CLUSTER_NAME}"

echo "=== 3. Building & Pushing Docker Image ==="
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin "${ECR_URL}"
docker build -t "${ECR_URL}:v1.0.0" .
docker push "${ECR_URL}:v1.0.0"

echo "=== 4. Deploying to Kubernetes ==="
kubectl apply -f k8s/kyverno.yaml
kubectl apply -f k8s/networkpolicy.yaml
kubectl apply -f k8s/deployment.yaml
kubectl set image deployment/number-reverser number-reverser="${ECR_URL}:v1.0.0" -n number-reverser
kubectl rollout status deployment/number-reverser -n number-reverser --timeout=120s

echo "Deployment complete!"
