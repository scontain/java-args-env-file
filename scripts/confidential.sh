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
CLUSTER_ADDR="127.0.0.1"
CAS_ADDR="cas.default"
CVM_MODE=false

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
  --namespace | -n <ns>     Kubernetes namespace to use in templates
  --pullsecret <name>       Kubernetes pull secret name (default: sconeapps)
  --k8s-scone-path <path>   Local path to k8s-scone repo (default: $K8S_SCONE_PATH)
  --cas-addr <name.ns>      CAS service to use (default: cas.default)
  --cluster-addr <addr>     Address to remote connect to the CAS (default: $CLUSTER_ADDR)
  --cvm                     Enable CVM/TDX mode (unlocks TDX-related fields in templates)
  --help | -h               Show this help message

⚠️  NOTE: You must run the first script BEFORE this to build and generate manifests.
EOF
}

substitute_template() {
  local input=$1
  local output=$2

  local sed_expr=(
    -e "s|{{REPO}}|${REPO}|g"
    -e "s|{{TAG}}|${TAG}|g"
    -e "s|{{PULLSECRET}}|${PULLSECRET:-sconeapps}|g"
    -e "s|{{CLUSTER_ADDR}}|${CLUSTER_ADDR}|g"
    -e "s|{{CAS_ADDR}}|${CAS_ADDR}|g"
  )

  if [[ -n "${NAMESPACE:-}" ]]; then
    sed_expr+=(-e "s|{{NAMESPACE}}|${NAMESPACE}|g")
  else
    sed_expr+=(-e "/namespace: {{NAMESPACE}}/d")
  fi

  if $CVM_MODE; then
    # Delete only the markers, keep the lines inside the block
    sed_expr+=(
      -e "/{{IF_CVM}}/d"
      -e "/{{END_IF}}/d"
    )
  else
    # Remove entire blocks between markers (inclusive)
    sed_expr+=(
      -e "/{{IF_CVM}}/,/{{END_IF}}/d"
    )
  fi

  sed "${sed_expr[@]}" "$input" > "$output"
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

  check_command() {
    command -v "$1" &>/dev/null
  }

  if ! dpkg-query -W -f='${Status}' gcc-multilib 2>/dev/null | grep "ok installed" &>/dev/null; then
    echo "📥 Installing gcc-multilib..."
    sudo apt update
    sudo apt -y install gcc-multilib
  else
    echo "✔️ gcc-multilib is already installed."
  fi

  if ! check_command rustc; then
    echo -e "${RED}❌ Rust is not installed. Please install it from https://rustup.rs/${NC}"
    exit 1
  else
    echo "✔️ Rust is already installed."
  fi

  if ! check_command cosign; then
    echo "📥 Installing Cosign..."
    curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
    sudo mv cosign-linux-amd64 /usr/local/bin/cosign
    sudo chmod +x /usr/local/bin/cosign
  else
    echo "✔️ Cosign is already installed."
  fi

  if ! check_command docker; then
    echo -e "${RED}❌ Docker is not installed. Please install it from https://docs.docker.com/engine/install/ubuntu/${NC}"
    exit 1
  else
    echo "✔️ Docker is already installed."
  fi

  local missing=()
  for cmd in kubectl yq sed gh pkg-config jq; do
    if ! check_command "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ! dpkg -s libssl-dev &>/dev/null; then
    missing+=("libssl-dev")
  fi

  if [ ${#missing[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing required tools/packages:${NC} ${missing[*]}"
    exit 1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ No Kubernetes cluster detected via kubectl. Is your cluster running?${NC}"
    exit 1
  fi

  echo -e "${YELLOW}🔍 Verifying CAS resource via 'kubectl get cas -A'...${NC}"
  CAS_NAME="${CAS_ADDR%%.*}"
  CAS_NAMESPACE="${CAS_ADDR#*.}"

  CAS_PHASE=$(kubectl get cas -A -o json | jq -r --arg name "$CAS_NAME" --arg ns "$CAS_NAMESPACE" '
    .items[] 
    | select(.metadata.name == $name and .metadata.namespace == $ns) 
    | .status.phase')

  if [[ -z "$CAS_PHASE" ]]; then
    echo -e "${RED}❌ No CAS resource named '${CAS_NAME}' found in namespace '${CAS_NAMESPACE}'.${NC}"
    exit 1
  fi

  if [[ "$CAS_PHASE" != "HEALTHY" ]]; then
    echo -e "${RED}❌ CAS '${CAS_NAME}' is not healthy. PHASE=${CAS_PHASE}${NC}"
    exit 1
  fi

  echo -e "${GREEN}✔️ CAS '${CAS_NAME}' is healthy (PHASE=$CAS_PHASE).${NC}"

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

  echo -e "${YELLOW}📦 Checking required container images...${NC}"
  images=(
    "registry.scontain.com/scone.cloud/sconecli"
    "registry.scontain.com/scone.cloud/sconecli:5.9.0-rc.11"
    "registry.scontain.com/public-images/glibc:2.35-v4"
    "registry.scontain.com/public-images/glibc:2.39-v3"
    "registry.scontain.com/cicd/base/runtime-ubuntu20.04:5.10.0-rc.1"
  )
  for image in "${images[@]}"; do
    if ! docker pull --quiet "$image" &>/dev/null; then
      echo -e "${RED}❌ Cannot pull Docker image: $image${NC}"
      exit 1
    fi
  done

  echo -e "${GREEN}✔️ All prerequisites are OK.${NC}"
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --namespace | -n) NAMESPACE="$2"; shift 2 ;;
    --pullsecret) PULLSECRET="$2"; shift 2 ;;
    --k8s-scone-path) K8S_SCONE_PATH="$2"; shift 2 ;;
    --cas-addr) CAS_ADDR="$2"; shift 2 ;;
    --cluster-addr) CLUSTER_ADDR="$2"; shift 2 ;;
    --cvm) CVM_MODE=true; shift ;;
    --help | -h) print_help; exit 0 ;;
    *) echo -e "${RED}❌ Unknown option: $1${NC}"; print_help; exit 1 ;;
  esac
done

# Validate CVM dependencies
if $CVM_MODE && [[ -z "${CLUSTER_ADDR:-}" ]]; then
  echo -e "${RED}❌ The --cluster-addr flag must be set when using --cvm mode.${NC}"
  exit 1
fi

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
yq ea 'select(fileIndex >= 0)' $(find "$GENERATED_DIR" -name '*.yaml' ! -name '*initidata*') > "$MANIFEST_FILE"

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

echo -e "${YELLOW}🛡️ Running k8s-scone on $MANIFEST_FILE...${NC}"
"$K8S_SCONE_PATH/target/debug/k8s-scone" from -y "$MANIFEST_FILE"

MANIFEST_RENDERED="generated/manifest.cleaned.yaml"
if [[ -f "$MANIFEST_RENDERED" ]]; then
  echo -e "${GREEN}✅ Confidential manifest: $MANIFEST_RENDERED${NC}"
else
  echo -e "${RED}❌ Error: $MANIFEST_RENDERED not created${NC}"
  exit 1
fi

echo -e "${YELLOW}🚀 Pushing image: ${REPO}:${TAG}-scone${NC}"
docker push "${REPO}:${TAG}-scone"

echo -e "${GREEN}🎉 Confidentialization completed successfully.${NC}"
