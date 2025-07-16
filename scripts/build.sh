#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="registry.scontain.com/workshop/java-cli-env-reader"
TAG="latest"
PULLSECRET="sconeapps"
NAMESPACE=""
NO_CACHE=false
BUNDLE_MANIFESTS=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Colo

REPO_REGEX="^([a-z0-9]+([._-]?[a-z0-9]+)*/?)+$"
TAG_REGEX='^[A-Za-z0-9_.-]{1,128}$'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build and push Docker image, and generate Kubernetes manifests from templates.

Options:
  --repo <repo>         Docker repository (default: '$REPO')
  --tag <tag>           Docker image tag (default: '$TAG')
  --pullsecret <name>   Kubernetes imagePullSecret name (default: '$PULLSECRET')
  --namespace, -n <ns>  Kubernetes namespace to inject into manifests (default: '$NAMESPACE')
  --no-cache            Disable Docker build cache (force image rebuild)
  --bundle-manifests    Bundle the Manifests into one yaml file ('$(realpath "$SCRIPT_DIR/../generated/manifest.yaml")')
  --help                Show this help message


Examples:
  $0
  $0 --repo ghcr.io/me/myapp --tag v1.2.3 --pullsecret mysecret -n devspace
EOF
}

check_prerequisites() {
  echo -e "${YELLOW}Checking prerequisites...${NC}"

  # Check kubectl
  if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}Error: kubectl is not installed.${NC}"
    exit 1
  fi

  # Check helm
  if ! command -v yq &>/dev/null; then
    echo -e "${RED}Error: yq is not installed.${NC}"
    exit 1
  fi

  if ! command -v sed &>/dev/null; then
    echo -e "${RED}Error: sed is not installed.${NC}"
    exit 1
  fi

  # Check docker
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: docker is not installed.${NC}"
    exit 1
  fi

  echo -e "${GREEN}All prerequisites are met.${NC}"
}

check_prerequisites

apply_template_params() {
  local local_filepath=$1
  local local_output=$2
  if [[ -n "$NAMESPACE" ]]; then
    sed -e "s|{{REPO}}|${REPO}|g" \
      -e "s|{{TAG}}|${TAG}|g" \
      -e "s|{{IMAGE_ID}}|${IMAGE_ID}|g" \
      -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
      -e "s|{{NAMESPACE}}|${NAMESPACE}|g" \
      "$local_filepath" >"$local_output"
  else
    sed -e "s|{{REPO}}|${REPO}|g" \
      -e "s|{{TAG}}|${TAG}|g" \
      -e "s|{{IMAGE_ID}}|${IMAGE_ID}|g" \
      -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
      -e "/namespace: {{NAMESPACE}}/d" \
      "$local_filepath" >"$local_output"
  fi
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
  --namespace | -n)
    NAMESPACE="$2"
    shift 2
    ;;
  --no-cache)
    NO_CACHE=true
    shift
    ;;
  --bundle-manifests)
    BUNDLE_MANIFESTS=true
    shift
    ;;
  --help | -h)
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
[[ "$REPO" =~ $REPO_REGEX ]] || {
  echo "❌ Invalid repo: $REPO"
  exit 1
}
[[ "$TAG" =~ $TAG_REGEX ]] || {
  echo "❌ Invalid tag: $TAG"
  exit 1
}

echo "📦 Building Docker image: $REPO:$TAG"
BUILD_ARGS=()
$NO_CACHE && BUILD_ARGS+=(--no-cache --pull)
docker build "${BUILD_ARGS[@]}" --quiet -t "${REPO}:${TAG}" -f $SCRIPT_DIR/../Dockerfile $SCRIPT_DIR/../

echo "🚀 Pushing image to $REPO:$TAG"
docker push "${REPO}:${TAG}"
IMAGE_ID=$(docker inspect --format='{{index .RepoDigests 0}}'  "${REPO}:${TAG}" | tr -d '\n')

echo "🛠️ Generating Kubernetes manifests"
mkdir -p $SCRIPT_DIR/../generated

for filepath in $SCRIPT_DIR/../manifests/*.template.yaml; do
  filename=$(basename -- "$filepath")
  template="${filename%.template.yaml}"
  output="$SCRIPT_DIR/../generated/$template.yaml"
  echo "🔧 Creating $output for $template"
  apply_template_params $filepath $output
done
echo ✅ All manifests generated in $(realpath "$SCRIPT_DIR/../generated")
[[ -n "$NAMESPACE" ]] && echo "📂 Namespace injected: $NAMESPACE"

if [ $BUNDLE_MANIFESTS == true ]; then
  yq ea 'select(fileIndex >= 0)' $(find $SCRIPT_DIR/../generated -type f -name "*.yaml" ! -name "*.template.yaml") >$SCRIPT_DIR/../generated/manifest.native.yaml
  echo ✅ Bundle manifest stored in $(realpath "$SCRIPT_DIR/../generated/manifest.native.yaml")
fi

