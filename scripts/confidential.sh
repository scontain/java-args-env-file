#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="docker.io/dandax123/java-cli-env-reader"
TAG="latest"
PULLSECRET="sconeapps"
NAMESPACE=""
NO_CACHE=false
BUNDLE_MANIFESTS=true
K8S_SCONE_PATH=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REPO_REGEX="^([a-z0-9]+([._-]?[a-z0-9]+)*/?)+$"
TAG_REGEX='^[A-Za-z0-9_.-]{1,128}$'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build and push Docker image, and generate Kubernetes manifests from templates.

Options:
  --repo <repo>             Docker repository (default: $REPO)
  --tag <tag>               Docker image tag (default: $TAG)
  --pullsecret <name>       Kubernetes imagePullSecret name (default: $PULLSECRET)
  --namespace, -n <ns>      Kubernetes namespace to inject into manifests
  --no-cache                Disable Docker build cache (force image rebuild)
  --bundle-manifests        Bundle the Manifests into one yaml file
  --k8s-scone-path <path>   Path where to clone and build k8s-scone repo
  --help                    Show this help message

Examples:
  $0
  $0 --repo ghcr.io/me/myapp --tag v1.2.3 --pullsecret mysecret -n devspace
EOF
}

check_prerequisites() {
  echo -e "${YELLOW}Checking prerequisites...${NC}"

  # Helper function for checking command presence
  check_command() {
    command -v "$1" &>/dev/null
  }

  # Install gcc-multilib if missing
  if ! dpkg-query -W -f='${Status}' gcc-multilib 2>/dev/null | grep "ok installed" &>/dev/null; then
    echo "📥 Installing gcc-multilib..."
    sudo apt update
    sudo apt -y install gcc-multilib
  else
    echo "✔️ gcc-multilib is already installed."
  fi

  # Check Rust compiler
  if ! check_command rustc; then
    echo -e "${RED}❌ Rust is not installed. Please install it from https://rustup.rs/${NC}"
    exit 1
  else
    echo "✔️ Rust is already installed."
  fi

  # Check Cosign, install if missing
  if ! check_command cosign; then
    echo "📥 Installing Cosign..."
    curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
    sudo mv cosign-linux-amd64 /usr/local/bin/cosign
    sudo chmod +x /usr/local/bin/cosign
  else
    echo "✔️ Cosign is already installed."
  fi

  # Check Docker
  if ! check_command docker; then
    echo -e "${RED}❌ Docker is not installed. Please install it from https://docs.docker.com/engine/install/ubuntu/${NC}"
    exit 1
  else
    echo "✔️ Docker is already installed."
  fi

  # Other required commands
  local missing=()
  for cmd in kubectl yq sed gh pkg-config; do
    if ! check_command "$cmd"; then
      missing+=("$cmd")
    fi
  done

  # Check for libssl-dev (Debian/Ubuntu)
  if ! dpkg -s libssl-dev &>/dev/null; then
    missing+=("libssl-dev")
  fi

  if [ ${#missing[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing required tools/packages:${NC} ${missing[*]}"
    exit 1
  fi

  # Kubernetes cluster check
  if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ No Kubernetes cluster detected via kubectl. Is your cluster running?${NC}"
    exit 1
  fi

  echo -e "${GREEN}✔️ All required commands, packages, and cluster access are OK.${NC}"

  # Check GitHub and GitLab repo access as before
  echo -e "${YELLOW}🔐 Checking GitHub/GitLab repository access...${NC}"
  github_repos=(
    "scontain/k8s-scone"
    "scontain/lib-sconify"
    "scontain/cargo-sconify"
    "scontain/signpolicy"
  )
  for repo in "${github_repos[@]}"; do
    if ! gh repo view "$repo" &>/dev/null; then
      echo -e "${RED}❌ Cannot access GitHub repo: $repo${NC}"
      exit 1
    fi
  done

  if ! git ls-remote "https://gitlab.scontain.com/amand1o/cvm-mode.git" &>/dev/null; then
    echo -e "${RED}❌ Cannot access GitLab repo: amand1o/cvm-mode${NC}"
    exit 1
  fi

  echo -e "${GREEN}✔️ GitHub and GitLab access OK.${NC}"

  # Check required container images
  echo -e "${YELLOW}📦 Checking required container images...${NC}"
  images=(
    "registry.scontain.com/scone.cloud/sconecli"
    "registry.scontain.com/scone.cloud/sconecli:5.9.0-rc.11"
    "registry.scontain.com/cicd/base/runtime-ubuntu20.04"
    "registry.scontain.com/cicd/base/runtime-ubuntu20.04:5.10.0-rc.1"
    "registry.scontain.com/public-images/glibc:2.35-v4"
  )
  for image in "${images[@]}"; do
    if ! docker pull --quiet "$image" &>/dev/null; then
      echo -e "${RED}❌ Cannot pull Docker image: $image${NC}"
      exit 1
    fi
  done

  echo -e "${GREEN}✔️ All required container images are available.${NC}"
}


apply_template_params() {
  local local_filepath=$1
  local local_output=$2
  if [[ -n "$NAMESPACE" ]]; then
    sed -e "s|{{REPO}}|${REPO}|g" \
      -e "s|{{TAG}}|${TAG}|g" \
      -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
      -e "s|{{NAMESPACE}}|${NAMESPACE}|g" \
      "$local_filepath" >"$local_output"
  else
    sed -e "s|{{REPO}}|${REPO}|g" \
      -e "s|{{TAG}}|${TAG}|g" \
      -e "s|{{PULLSECRET}}|${PULLSECRET}|g" \
      -e "/namespace: {{NAMESPACE}}/d" \
      "$local_filepath" >"$local_output"
  fi
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --pullsecret) PULLSECRET="$2"; shift 2 ;;
    --namespace | -n) NAMESPACE="$2"; shift 2 ;;
    --no-cache) NO_CACHE=true; shift ;;
    --bundle-manifests) BUNDLE_MANIFESTS=true; shift ;;
    --k8s-scone-path) K8S_SCONE_PATH="$2"; shift 2 ;;
    --help | -h) print_help; exit 0 ;;
    *) echo "❌ Unknown option: $1"; echo "Run with --help for usage."; exit 1 ;;
  esac
done

check_prerequisites

# Clone and build k8s-scone repo if path is provided
if [[ -n "$K8S_SCONE_PATH" ]]; then
  if [ ! -d "$K8S_SCONE_PATH" ]; then
    echo "📥 Cloning k8s-scone repo into $K8S_SCONE_PATH"
    git clone https://github.com/scontain/k8s-scone.git "$K8S_SCONE_PATH"
    cd "$K8S_SCONE_PATH"
    git fetch
    git checkout amand1o/pet-clinic
    cargo build
    cd - >/dev/null
  else
    echo "✅ Using existing k8s-scone repo at $K8S_SCONE_PATH"
  fi
fi

# Validate repo and tag
[[ "$REPO" =~ $REPO_REGEX ]] || { echo "❌ Invalid repo: $REPO"; exit 1; }
[[ "$TAG" =~ $TAG_REGEX ]] || { echo "❌ Invalid tag: $TAG"; exit 1; }

echo "📦 Building Docker image: $REPO:$TAG"
BUILD_ARGS=()
$NO_CACHE && BUILD_ARGS+=(--no-cache --pull)
docker build "${BUILD_ARGS[@]}" -t "${REPO}:${TAG}" -f "$SCRIPT_DIR/../Dockerfile" "$SCRIPT_DIR/../"

echo "🚀 Pushing image to $REPO:$TAG"
docker push "${REPO}:${TAG}"

echo "🛠️ Generating Kubernetes manifests"
OUTPUT_DIR="$SCRIPT_DIR/../generated"
mkdir -p "$OUTPUT_DIR"

generate_from_templates() {
  local input_folder=$1
  echo "📁 Processing folder: $(basename "$input_folder")"
  for filepath in "$input_folder"/*.template.yaml; do
    filename=$(basename -- "$filepath")
    template="${filename%.template.yaml}"
    output="$OUTPUT_DIR/$template.yaml"
    echo "🔧 Creating $output for $template"
    apply_template_params "$filepath" "$output"
  done
}

generate_from_templates "$SCRIPT_DIR/../manifests"
generate_from_templates "$SCRIPT_DIR/../confidential"

if [ "$BUNDLE_MANIFESTS" = true ]; then
  echo "📦 Bundling ALL manifests into $OUTPUT_DIR/manifest.yaml"
  yq ea 'select(fileIndex >= 0)' $(find "$OUTPUT_DIR" -type f -name "*.yaml" ! -name "*.template.yaml") >"$OUTPUT_DIR/manifest.yaml"
fi

echo "✅ All manifests generated"
[[ -n "$NAMESPACE" ]] && echo "📂 Namespace injected: $NAMESPACE"

