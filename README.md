# Jenkins CI/CD Pipeline for Containerized Applications

A Jenkins declarative pipeline that builds a Docker image, deploys it to
dev, UAT or production, verifies the release, and rolls back to the last
stable image when a deployment fails.

## Pipeline flow

```
Checkout
   ↓
Record previous image      ← saved so a failed release can be reverted
   ↓
Build image                ← tagged with env + build number + git SHA
   ↓
Push to registry           ← skipped for dev
   ↓
Manual approval            ← production only
   ↓
Deploy                     ← scripts/deploy.sh
   ↓
Verify                     ← scripts/health-check.sh
   ↓
on failure → Rollback      ← scripts/rollback.sh
```

## What each piece does

| File | Purpose |
|---|---|
| `Jenkinsfile` | Declarative pipeline with parameters, approval gate and rollback in `post { failure }` |
| `Dockerfile` | Slim image, non-root user, `HEALTHCHECK`, git SHA baked in as a label |
| `docker-compose.yml` | App + PostgreSQL with health checks and service dependencies |
| `scripts/deploy.sh` | Pulls the image, recreates the service, waits for the container to report healthy |
| `scripts/rollback.sh` | Restores the previously running image and verifies it |
| `scripts/health-check.sh` | Checks the health endpoint, TLS expiry, container state and recent error logs |
| `env/*.env.example` | Per-environment configuration templates |

## Environment separation

Each environment has its own config file and its own image tag, so a change
is always verified in a lower environment before it reaches production.

| Environment | Image tag | Registry push | Approval |
|---|---|---|---|
| dev | `dev-<build>` | no | no |
| uat | `uat-<build>` | yes | no |
| prod | `prod-<build>` | yes | **yes** |

## Rollback

The pipeline records the image the container is currently running **before**
it builds anything:

```groovy
env.PREVIOUS_IMAGE = sh(
    script: "docker inspect --format='{{.Config.Image}}' ${APP_NAME}",
    returnStdout: true
).trim()
```

If any stage fails, `post { failure }` calls `rollback.sh` with that image,
brings the previous version back up and waits for it to report healthy. If
the rollback itself does not go healthy, the script exits non-zero so the
build stays red and the on-call engineer is alerted.

## Setup

**1. Jenkins credentials**

Add a username/password credential with the ID `docker-registry` for your
registry login.

**2. Pipeline job**

Create a Pipeline job, point it at this repository, and set the script path
to `Jenkinsfile`.

**3. Environment files**

```bash
cp env/dev.env.example env/dev.env
cp env/uat.env.example env/uat.env
cp env/prod.env.example env/prod.env
```

Fill in the real values. These files are gitignored.

**4. Run**

Build with parameters, pick the environment and branch.

## Running a deploy manually

```bash
./scripts/deploy.sh uat registry.example.com/payment-api:uat-42
./scripts/health-check.sh uat
./scripts/rollback.sh uat registry.example.com/payment-api:uat-41
```

## Notes

Based on a deployment workflow I built and ran for a fintech payment
platform. Registry URLs, hostnames and credentials here are placeholders —
no company-specific details are included.
