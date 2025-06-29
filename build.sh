#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="registry.scontain.com/workshop/java-cli-env-reader"
TAG="latest"
PULLSECRET="sconeapps"
NAMESPACE=""
NO_CACHE=false

REPO_REGEX="^([a-z0-9]+([._-]?[a-z0-9]+)*/?)+$"
TAG_REGEX='^[A-Za-z0-9_.-]{1,128}$'

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build and push Docker image, and generate Kubernetes manifests from templates.

Options:
  --repo <repo>         Docker repository (default: $REPO)
  --tag <tag>           Docker image tag (default: $TAG)
  --pullsecret <name>   Kubernetes imagePullSecret name (default: $PULLSECRET)
  --namespace, -n <ns>  Kubernetes namespace to inject into manifests
  --no-cache            Disable Docker build cache (force image rebuild)
  --help                Show this help message

Examples:
  $0
  $0 --repo ghcr.io/me/myapp --tag v1.2.3 --pullsecret mysecret -n devspace
EOF
}

# Parse CLI arguments
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
    --namespace|-n)
      NAMESPACE="$2"
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

# Validate repo and tag
[[ "$REPO" =~ $REPO_REGEX ]] || { echo "❌ Invalid repo: $REPO"; exit 1; }
[[ "$TAG" =~ $TAG_REGEX ]]   || { echo "❌ Invalid tag: $TAG"; exit 1; }

echo "📦 Building Docker image: $REPO:$TAG"
BUILD_ARGS=()
$NO_CACHE && BUILD_ARGS+=(--no-cache --pull)
docker build "${BUILD_ARGS[@]}" -t "${REPO}:${TAG}" .

echo "🚀 Pushing image to $REPO:$TAG"
docker push "${REPO}:${TAG}"

echo "🛠️ Generating Kubernetes manifests"
for template in *.template.yaml; do
  output="${template%.template.yaml}.yaml"
  echo "🔧 Creating $output"

  if [[ -n "$NAMESPACE" ]]; then
    sed -e "s|{{REPO}}|${REPO}|g" \
        -e "s|{{TAG}}|${TAG}|g" \
        -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
        -e "s|{{NAMESPACE}}|${NAMESPACE}|g" \
        "$template" > "$output"
  else
    sed -e "s|{{REPO}}|${REPO}|g" \
        -e "s|{{TAG}}|${TAG}|g" \
        -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
        -e "/namespace: {{NAMESPACE}}/d" \
        "$template" > "$output"
  fi
done

echo "✅ All manifests generated"
[[ -n "$NAMESPACE" ]] && echo "📂 Namespace injected: $NAMESPACE"
