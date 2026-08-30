$ErrorActionPreference = "Stop"
Write-Host "=== Destroying Kubernetes & AWS Infrastructure ===" -ForegroundColor Red
kubectl delete namespace number-reverser --ignore-not-found=true

Push-Location terraform
try {
    terraform destroy -auto-approve
}
finally {
    Pop-Location
}
Write-Host "Teardown complete! Zero residual AWS cloud spend." -ForegroundColor Green
