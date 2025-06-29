#!/usr/bin/env bash
set -euo pipefail

# Default context (optional: leave empty to use current context)
KUBECTL_CONTEXT=""

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploys Kubernetes manifests (deployment.yaml, configmap.yaml, secret.yaml)

Options:
  --context <name>   Kubernetes context to use (default: current context)
  --help             Show this help message and exit

Examples:
  $0
  $0 --context my-cluster
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      KUBECTL_CONTEXT="$2"
      shift 2
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

# Check required files
for file in configmap.yaml secret.yaml deployment.yaml; do
  if [[ ! -f "$file" ]]; then
    echo "❌ Required manifest file not found: $file"
    exit 1
  fi
done

# Build kubectl command
KUBECTL="kubectl"
if [[ -n "$KUBECTL_CONTEXT" ]]; then
  KUBECTL="$KUBECTL --context $KUBECTL_CONTEXT"
fi

# Apply manifests
echo "🚀 Deploying resources using context: ${KUBECTL_CONTEXT:-<current>}"
$KUBECTL apply -f configmap.yaml
$KUBECTL apply -f secret.yaml
$KUBECTL apply -f deployment.yaml

echo "✅ Deployment complete."
