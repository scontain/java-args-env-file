#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="docker.io/dandax123/java-cli-env-reader"
TAG="latest"
K8S_SCONE_PATH="${HOME}/k8s-scone"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
GENERATED_DIR="$SCRIPT_DIR/../generated"
MANIFEST_FILE="$GENERATED_DIR/manifest.yaml"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
CONFIDENTIAL_DIR="$SCRIPT_DIR/../confidential"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Confidentialize previously built Docker image and generated Kubernetes manifests.

Options:
  --repo <repo>             Docker image name (default: $REPO)
  --tag <tag>               Docker image tag (default: $TAG)
  --k8s-scone-path <path>   Local path to k8s-scone repo (default: $K8S_SCONE_PATH)
  --help                    Show this help message

⚠️  NOTE: You must run the first script BEFORE this to build and generate manifests.
EOF
}

substitute_template() {
  local input=$1
  local output=$2
  if [[ -n "${NAMESPACE:-}" ]]; then
    sed -e "s|{{REPO}}|${REPO}|g" \
        -e "s|{{TAG}}|${TAG}|g" \
        -e "s|{{PULLSECRET}}|${PULLSECRET:-sconeapps}|g" \
        -e "s|{{NAMESPACE}}|${NAMESPACE}|g" \
        "$input" > "$output"
  else
    sed -e "s|{{REPO}}|${REPO}|g" \
        -e "s|{{TAG}}|${TAG}|g" \
        -e "s|{{PULLSECRET}}|${PULLSECRET:-sconeapps}|g" \
        -e "/namespace: {{NAMESPACE}}/d" \
        "$input" > "$output"
  fi
}

generate_confidential_manifests() {
  echo -e "${YELLOW}🔐 Generating confidential manifests...${NC}"
  for filepath in "$CONFIDENTIAL_DIR"/*.template.yaml; do
    [ -e "$filepath" ] || continue
    filename=$(basename -- "$filepath")
    template="${filename%.template.yaml}"
    output="$GENERATED_DIR/$template.yaml"
    echo "🔧 Rendering confidential manifest: $output"
    substitute_template "$filepath" "$output"
  done
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
    "registry.scontain.com/public-images/glibc:2.35-v4"
    "registry.scontain.com/public-images/glibc:2.39-v3"
    "registry.scontain.com/cicd/base/runtime-ubuntu20.04:5.10.0-rc.1"
    "registry.scontain.com/scone.cloud/sconecli:5.9.0-rc.11"
  )
  for image in "${images[@]}"; do
    if ! docker pull --quiet "$image" &>/dev/null; then
      echo -e "${RED}❌ Cannot pull Docker image: $image${NC}"
      exit 1
    fi
  done

  echo -e "${GREEN}✔️ All required container images are available.${NC}"
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --namespace | -n) NAMESPACE="$2"; shift 2 ;;
    --pullsecret) PULLSECRET="$2"; shift 2 ;;
    --k8s-scone-path) K8S_SCONE_PATH="$2"; shift 2 ;;
    --help | -h) print_help; exit 0 ;;
    *) echo -e "${RED}❌ Unknown option: $1${NC}"; print_help; exit 1 ;;
  esac
done

# Ensure base manifests exist
if [[ ! -d "$GENERATED_DIR" ]]; then
  echo -e "${RED}❌ Missing generated folder: $GENERATED_DIR${NC}"
  echo "💡 Run the base script first to build and generate manifests."
  exit 1
fi

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo -e "${RED}❌ Missing manifest file: $MANIFEST_FILE${NC}"
  echo "💡 Run the base script first to generate manifest.yaml."
  exit 1
fi

check_prerequisites
generate_confidential_manifests

echo -e "${YELLOW}📦 Bundling all manifests...${NC}"
yq ea 'select(fileIndex >= 0)' "$GENERATED_DIR"/*.yaml > "$MANIFEST_FILE"

# Ensure k8s-scone is built
if [[ ! -x "$K8S_SCONE_PATH/target/debug/k8s-scone" ]]; then
  echo -e "${YELLOW}📥 Cloning and building k8s-scone...${NC}"
  git clone https://github.com/scontain/k8s-scone.git "$K8S_SCONE_PATH"
  cd "$K8S_SCONE_PATH"
  git fetch
  git checkout amand1o/pet-clinic
  cargo build
  cd - >/dev/null
else
  echo -e "${GREEN}✅ Using k8s-scone at $K8S_SCONE_PATH${NC}"
fi

# Run k8s-scone
echo -e "${YELLOW}🛡️ Running k8s-scone on $MANIFEST_FILE...${NC}"
"$K8S_SCONE_PATH/target/debug/k8s-scone" from -y "$MANIFEST_FILE"

MANIFEST_RENDERED="manifest.cleaned.yaml"
if [[ -f "$MANIFEST_RENDERED" ]]; then
  echo -e "${GREEN}✅ Confidential manifest: $MANIFEST_RENDERED${NC}"
else
  echo -e "${RED}❌ Error: $MANIFEST_RENDERED not created${NC}"
  exit 1
fi

# Push confidential image
echo -e "${YELLOW}🚀 Pushing image: ${REPO}:${TAG}-scone${NC}"
docker push "${REPO}:${TAG}-scone"

echo -e "${GREEN}🎉 Confidentialization completed successfully.${NC}"
