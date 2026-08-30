pipeline {
    agent any

    environment {
        AWS_REGION         = 'ap-south-1'
        APP_NAME           = 'number-reverser'
        CLUSTER_NAME       = 'number-reverser-cluster'
        
        // ECR & Registry Credentials (Amazon ECR plugin format: ecr:<region>:<credentials-id>)
        registryCredential = 'ecr:ap-south-1:aws-credentials'
        appRegistry        = '374857852848.dkr.ecr.ap-south-1.amazonaws.com/number-reverser'
        ecrRegistry        = 'https://374857852848.dkr.ecr.ap-south-1.amazonaws.com'
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
                sh "docker build --no-cache -t ${appRegistry}:${env.BUILD_NUMBER} ."
            }
        }

        stage('Trivy Security Scan') {
            steps {
                sh "trivy image --cache-dir .trivy-cache --severity CRITICAL,HIGH --ignore-unfixed --exit-code 0 ${appRegistry}:${env.BUILD_NUMBER}"
            }
        }

        stage('Generate SBOM (Syft)') {
            steps {
                sh "syft ${appRegistry}:${env.BUILD_NUMBER} -o spdx-json=sbom.spdx.json"
                archiveArtifacts artifacts: 'sbom.spdx.json', allowEmptyArchive: true
            }
        }

        stage('Upload App Image') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -ex
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ecrRegistry}
                        docker push ${appRegistry}:${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Cosign Sign & Verify') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                                file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
                    sh '''
                        set -ex
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        export COSIGN_PASSWORD="${COSIGN_PASSWORD:-}"
                        
                        IMAGE_URI="${appRegistry}:${BUILD_NUMBER}"
                        
                        # 1. Sign container image
                        cosign sign --key "${COSIGN_KEY}" --yes "${IMAGE_URI}"
                        
                        # 2. Derive matching public key and cryptographically verify signature
                        cosign public-key --key "${COSIGN_KEY}" > cosign_extracted.pub
                        cosign verify --key cosign_extracted.pub "${IMAGE_URI}"
                    '''
                }
            }
        }

        stage('Deploy to EKS & Verify') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -ex
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
                        
                        # Apply Kyverno policies if CRDs are installed on the cluster
                        if kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then
                            kubectl apply -f k8s/kyverno.yaml
                        fi
                        
                        # Apply Deployment and NetworkPolicy
                        kubectl apply -f k8s/deployment.yaml
                        kubectl apply -f k8s/networkpolicy.yaml
                        
                        # Roll out the new immutable container image
                        kubectl set image deployment/number-reverser number-reverser=${appRegistry}:${BUILD_NUMBER} -n number-reverser
                        kubectl rollout status deployment/number-reverser -n number-reverser --timeout=180s
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    sh '''
                        set -ex
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
                        
                        kubectl port-forward svc/number-reverser 8000:80 -n number-reverser &
                        PF_PID=$!
                        sleep 6

                        # Verify healthz and reverse endpoints
                        curl -sf http://127.0.0.1:8000/healthz
                        curl -sf -X POST http://127.0.0.1:8000/api/v1/reverse -H "Content-Type: application/json" -d '{"number": 12345}' | grep 54321

                        kill $PF_PID 2>/dev/null || true
                        echo "All smoke tests passed successfully!"
                    '''
                }
            }
        }
    }
}
