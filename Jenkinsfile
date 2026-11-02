pipeline {
    agent any

    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'uat', 'prod'],
               description: 'Target environment')
        string(name: 'BRANCH', defaultValue: 'main',
               description: 'Branch to build')
    }

    environment {
        APP_NAME     = 'payment-api'
        REGISTRY     = 'registry.example.com'
        IMAGE        = "${REGISTRY}/${APP_NAME}"
        BUILD_TAG    = "${params.ENVIRONMENT}-${BUILD_NUMBER}"
        COMPOSE_FILE = 'docker-compose.yml'
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: "${params.BRANCH}",
                    url: 'https://github.com/mohdmudassirgithub/jenkins-docker-pipeline.git'
                sh 'git rev-parse --short HEAD > .git-sha'
                script {
                    env.GIT_SHA = readFile('.git-sha').trim()
                    echo "Building ${APP_NAME} from ${params.BRANCH} @ ${env.GIT_SHA}"
                }
            }
        }

        stage('Record previous image') {
            steps {
                script {
                    // Saved so a failed release can be rolled back to the last good image
                    env.PREVIOUS_IMAGE = sh(
                        script: "docker inspect --format='{{.Config.Image}}' ${APP_NAME} 2>/dev/null || echo 'none'",
                        returnStdout: true
                    ).trim()
                    echo "Current running image: ${env.PREVIOUS_IMAGE}"
                }
            }
        }

        stage('Build image') {
            steps {
                sh """
                    docker build \
                      --build-arg GIT_SHA=${env.GIT_SHA} \
                      -t ${IMAGE}:${BUILD_TAG} \
                      -t ${IMAGE}:${params.ENVIRONMENT}-latest \
                      .
                """
            }
        }

        stage('Push image') {
            when { expression { params.ENVIRONMENT != 'dev' } }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS')]) {
                    sh """
                        echo "\$REG_PASS" | docker login ${REGISTRY} -u "\$REG_USER" --password-stdin
                        docker push ${IMAGE}:${BUILD_TAG}
                        docker push ${IMAGE}:${params.ENVIRONMENT}-latest
                        docker logout ${REGISTRY}
                    """
                }
            }
        }

        stage('Approval') {
            when { expression { params.ENVIRONMENT == 'prod' } }
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Deploy ${IMAGE}:${BUILD_TAG} to PRODUCTION?",
                          ok: 'Deploy'
                }
            }
        }

        stage('Deploy') {
            steps {
                sh "./scripts/deploy.sh ${params.ENVIRONMENT} ${IMAGE}:${BUILD_TAG}"
            }
        }

        stage('Verify') {
            steps {
                sh "./scripts/health-check.sh ${params.ENVIRONMENT}"
            }
        }
    }

    post {
        failure {
            echo 'Release failed — rolling back to the last stable image'
            sh "./scripts/rollback.sh ${params.ENVIRONMENT} ${env.PREVIOUS_IMAGE}"
        }
        success {
            echo "Deployed ${IMAGE}:${BUILD_TAG} to ${params.ENVIRONMENT}"
        }
        always {
            sh 'docker image prune -f --filter "until=168h" || true'
        }
    }
}
