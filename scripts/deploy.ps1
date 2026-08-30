$ErrorActionPreference = "Stop"

Write-Host "=== 1. Provisioning AWS Infrastructure with Terraform ===" -ForegroundColor Cyan
Push-Location terraform
try {
    terraform init
    terraform apply -auto-approve
    $ClusterName = terraform output -raw cluster_name
    $EcrUrl = terraform output -raw ecr_repository_url
}
finally {
    Pop-Location
}

Write-Host "=== 2. Updating Kubeconfig ===" -ForegroundColor Cyan
aws eks update-kubeconfig --region ap-south-1 --name $ClusterName

Write-Host "=== 3. Building & Pushing Docker Image ===" -ForegroundColor Cyan
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin $EcrUrl
docker build -t "$($EcrUrl):v1.0.0" .
docker push "$($EcrUrl):v1.0.0"

Write-Host "=== 4. Deploying to Kubernetes ===" -ForegroundColor Cyan
kubectl apply -f k8s/kyverno.yaml
kubectl apply -f k8s/networkpolicy.yaml
kubectl apply -f k8s/deployment.yaml
kubectl set image deployment/number-reverser number-reverser="$($EcrUrl):v1.0.0" -n number-reverser
kubectl rollout status deployment/number-reverser -n number-reverser --timeout=120s

Write-Host "Deployment complete!" -ForegroundColor Green
