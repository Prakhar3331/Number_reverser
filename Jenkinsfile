pipeline {
    agent any

    environment {
        AWS_REGION         = 'ap-south-1'
        AWS_CREDENTIALS_ID = 'aws-credentials'
        AWS_ACCOUNT_ID     = '374857852848'
        APP_NAME           = 'number-reverser'
        CLUSTER_NAME       = 'number-reverser-cluster'
        
        IMAGE_TAG          = "v1.0.0-${env.BUILD_NUMBER}"
        ECR_REGISTRY       = "374857852848.dkr.ecr.ap-south-1.amazonaws.com"
        IMAGE_URI          = "374857852848.dkr.ecr.ap-south-1.amazonaws.com/number-reverser:v1.0.0-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Lint & Security Check') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet -r requirements-dev.txt
                    black --check app/
                    flake8 app/ --max-line-length=100
                    bandit -r app/ -ll -ii
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    . .venv/bin/activate
                    pytest -v --cov=app --cov-fail-under=90
                '''
            }
        }

        stage('Terraform Validation & Checkov') {
            steps {
                sh '''
                    terraform -chdir=terraform init -backend=false
                    terraform -chdir=terraform validate
                    . .venv/bin/activate
                    checkov -d terraform/ --framework terraform --soft-fail
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build --no-cache -t ${IMAGE_URI} -t ${APP_NAME}:local ."
            }
        }

        stage('Trivy Security Scan') {
            steps {
                sh "trivy image --cache-dir .trivy-cache --severity CRITICAL,HIGH --ignore-unfixed --exit-code 0 ${APP_NAME}:local"
            }
        }

        stage('Generate SBOM (Syft)') {
            steps {
                sh "syft ${APP_NAME}:local -o spdx-json=sbom.spdx.json"
                archiveArtifacts artifacts: 'sbom.spdx.json', allowEmptyArchive: true
            }
        }

        stage('Push to Amazon ECR') {
            steps {
                withCredentials([usernamePassword(credentialsId: env.AWS_CREDENTIALS_ID, usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        
                        # 1. Authenticate with ECR
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # 2. Tag and push both specific build tag and latest
                        docker tag ${APP_NAME}:local ${IMAGE_URI}
                        docker tag ${APP_NAME}:local ${ECR_REGISTRY}/${APP_NAME}:latest
                        
                        docker push ${IMAGE_URI}
                        docker push ${ECR_REGISTRY}/${APP_NAME}:latest
                    '''
                }
            }
        }

        stage('Cosign Sign & Verify') {
            steps {
                withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
                    sh '''
                        cosign sign --key "${COSIGN_KEY}" --yes "${IMAGE_URI}"
                        cosign verify --key cosign.pub "${IMAGE_URI}"
                    '''
                }
            }
        }

        stage('Deploy to EKS & Verify') {
            steps {
                withCredentials([usernamePassword(credentialsId: env.AWS_CREDENTIALS_ID, usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
                        
                        # Apply Kyverno policies, NetworkPolicy, and Deployment
                        kubectl apply -f k8s/kyverno.yaml
                        kubectl apply -f k8s/networkpolicy.yaml
                        kubectl apply -f k8s/deployment.yaml
                        
                        # Update to immutable deployed image
                        kubectl set image deployment/number-reverser number-reverser=${IMAGE_URI} -n number-reverser
                        kubectl rollout status deployment/number-reverser -n number-reverser --timeout=120s
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    kubectl port-forward svc/number-reverser 8000:80 -n number-reverser &
                    PF_PID=$!
                    sleep 3

                    # Verify health and reverse endpoint
                    curl -sf http://127.0.0.1:8000/healthz
                    curl -sf -X POST http://127.0.0.1:8000/api/v1/reverse -H "Content-Type: application/json" -d '{"number": 12345}' | grep 54321

                    kill $PF_PID
                    echo "Smoke tests passed!"
                '''
            }
        }
    }
}
