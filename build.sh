#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="registry.scontain.com/workshop/java-cli-env-reader"
TAG="latest"
PULLSECRET="sconeapps"
DEPLOYMENT_TEMPLATE="deployment.template.yaml"
DEPLOYMENT_OUTPUT="deployment.yaml"

# Regex patterns
REPO_REGEX="^([a-z0-9]+([._-]?[a-z0-9]+)*/?)+$"
TAG_REGEX='^[A-Za-z0-9_.-]{1,128}$'

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build and push the Docker image, and generate deployment.yaml.

Options:
  --repo <repo>         Docker repository (default: $REPO)
  --tag <tag>           Docker image tag (default: $TAG)
  --pullsecret <name>   Kubernetes imagePullSecret name (default: $PULLSECRET)
  --no-cache            Disable Docker build cache
  --help                Show this help message and exit

Examples:
  $0
  $0 --repo ghcr.io/me/myapp --tag v1.2.3 --pullsecret my-secret
EOF
}

NO_CACHE=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --pullsecret)
      PULLSECRET="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Run with --help for usage."
      exit 1
      ;;
  esac
done

# Validate input
[[ "$REPO" =~ $REPO_REGEX ]] || { echo "❌ Invalid repo: $REPO"; exit 1; }
[[ "$TAG" =~ $TAG_REGEX ]]   || { echo "❌ Invalid tag: $TAG"; exit 1; }

# Check template file
[[ -f "$DEPLOYMENT_TEMPLATE" ]] || {
  echo "❌ Template not found: $DEPLOYMENT_TEMPLATE"
  exit 1
}

# Build image
echo "📦 Building Docker image: $REPO:$TAG"
BUILD_ARGS=()
$NO_CACHE && BUILD_ARGS+=(--no-cache --pull)
docker build "${BUILD_ARGS[@]}" -t "${REPO}:${TAG}" .

# Push
echo "🚀 Pushing image to $REPO:$TAG"
docker push "${REPO}:${TAG}"

# Generate deployment manifest
echo "🛠️ Generating $DEPLOYMENT_OUTPUT"
sed -e "s|{{REPO}}|${REPO}|g" \
    -e "s|{{TAG}}|${TAG}|g" \
    -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
    "$DEPLOYMENT_TEMPLATE" > "$DEPLOYMENT_OUTPUT"

echo "✅ Done. Generated $DEPLOYMENT_OUTPUT with pull secret: $PULLSECRET"
