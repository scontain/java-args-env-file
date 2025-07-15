#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO="registry.scontain.com/workshop/java-cli-env-reader"
TAG="latest"
K8S_SCONE_PATH=""
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
GENERATED_DIR="$SCRIPT_DIR/../generated"
MANIFEST_FILE="$GENERATED_DIR/manifest.yaml"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
CONFIDENTIAL_DIR="$SCRIPT_DIR/../confidential"
CLUSTER_ADDR="127.0.0.1"
CAS_ADDR="cas.default"
CVM_MODE=false
TDX_MODE=false
SPLIT_MODE=false
APP_LABEL="arg-env"
BINARY_PATH="/opt/java/openjdk/bin/java"

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
  --split                   Enable split mode (can be used independently of --cvm)
  --help | -h               Show this help message

⚠️  NOTE: You must run the first script with --bundle-manifests flag BEFORE this to build and generate manifests.
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
    sed_expr+=(-e "s|{{NAMESPACE}}|  namespace: ${NAMESPACE}|g")
  else
    sed_expr+=(-e "/{{NAMESPACE}}/d")
  fi

  # Handle split mode independently
  if $SPLIT_MODE; then
    sed_expr+=(-e "s|{{SPLIT}}|split: true|g")
  else
    sed_expr+=(-e "s|{{SPLIT}}||g")
  fi

  # Handle CVM mode
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


register_image() {
  local key="$1"
  local image="$2"
  transformed=${image/@sha256:/:}
  echo "🔧 Registering image: $image as $transformed"
  docker tag "$image" "$transformed"
  cat > "$GENERATED_DIR/$key.yaml" <<EOF
apiVersion: scone.cloud/v1
kind: Register
metadata:
  name: $APP_LABEL         
spec:
  protected_image:   $transformed
  unprotected_image: $transformed # SGX
  enforce:           ["$BINARY_PATH"] # SGX
  tdx: $TDX_MODE
EOF
}

# Normalize image name (optional — you could also hash it)
normalize_image_key() {
  local image="$1"
  echo "$image" \
    | sed -e 's|/|__SLASH__|g' \
          -e 's/@/__AT__/g' \
          -e 's/:/__COLON__/g' \
          -e 's/\"/_/g' \
          -e 's|\.|__DOT__|g' 
}

# Associative array to keep track of seen images
declare -A seen_images

register_images() {
  # Define your image registration function

  # Loop through all YAML files
  FILES_TO_PARSE=$(find "$GENERATED_DIR" -name '*.yaml' ! -name '*initidata*' ! -name 'setup.yaml' ! -name 'manifest.yaml')
  for file in $FILES_TO_PARSE; do
    [[ -e "$file" ]] || continue
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*image:[[:space:]]*(.+)$ ]]; then
        image="${BASH_REMATCH[1]}"
        image="${image//\"/}"
        key=$(normalize_image_key "$image")
        if [[ -z "${seen_images[$key]+exists}" ]]; then
          seen_images["$key"]=1
          register_image "$key" "$image"
        fi
      fi
    done < "$file"
  done
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
    --cvm) CVM_MODE=true; TDX_MODE=true; shift ;;
    --split) SPLIT_MODE=true; shift ;;
    --help | -h) print_help; exit 0 ;;
    *) echo -e "${RED}❌ Unknown option: $1${NC}"; print_help; exit 1 ;;
  esac
done

# Try to find k8s-scone if not specified
if [[ -z "$K8S_SCONE_PATH" ]]; then
  K8S_SCONE_PATH="$(which k8s-scone 2>/dev/null || true)"
  if [[ -z "$K8S_SCONE_PATH" ]]; then
    echo -e "${RED}❌ k8s-scone not found in PATH${NC}"
    echo "💡 Please specify the path to k8s-scone using the --k8s-scone-path flag"
    exit 1
  fi
fi

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

if [[ ! -e "identity.pem" ]]; then
  echo -e "${YELLOW}📦 Generating a new identity.pem${NC}"
  openssl genrsa -3 -out "identity.pem" 3072
fi

generate_confidential_manifests
register_images

# find "$GENERATED_DIR" -name '*.yaml' ! -name '*initidata*' ! -name 'setup.yaml' ! -name 'manifest.yaml'

echo -e "${YELLOW}📦 Bundling all manifests...${NC}"
yq ea 'select(fileIndex >= 0)' $(find "$GENERATED_DIR" -name '*.yaml' ! -name '*initidata*') > "$MANIFEST_FILE"

echo -e "${YELLOW}🛡️ Running k8s-scone on $MANIFEST_FILE...${NC}"
$K8S_SCONE_PATH from -y "$MANIFEST_FILE"

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
