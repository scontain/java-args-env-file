#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

NAMESPACE=""
CONTEXT=""
HELP=false
CLUSTER_ONLY=false

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deletes all Kubernetes resources created from generated manifests.

Options:
  --namespace, -n <ns>   Target Kubernetes namespace (default: current context default)
  --cluster-only         Delete only the Kubernetes resources associated with the cluster, not the local files
  --context <ctx>        kubectl context to use
  --help                 Show this help message

Examples:
  $0
  $0 -n my_namespace
  $0 --namespace prod --context my-cluster
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  --namespace | -n)
    NAMESPACE="$2"
    shift 2
    ;;
  --context)
    CONTEXT="$2"
    shift 2
    ;;
  --cluster-only)
    CLUSTER_ONLY=true
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

# Compose kubectl base command
KUBECTL_CMD="kubectl"
[[ -n "$CONTEXT" ]] && KUBECTL_CMD+=" --context=$CONTEXT"
[[ -n "$NAMESPACE" ]] && KUBECTL_CMD+=" --namespace=$NAMESPACE"

# Delete all resources in the specified namespace
kubectl delete -f generated/configmap.yaml -f generated/deployment.yaml -f generated/secret.yaml || true

if $CLUSTER_ONLY; then
  echo "✅ Cluster resources deleted. Exiting without deleting local files."
  exit 0
fi

# Clean up all generated .yaml files
rm -rf $SCRIPT_DIR/../generated
rm -f arg-env.json
rm -f report.json
rm -f Dockerfile.*

echo "✅ Cleanup complete"
[[ -n "$NAMESPACE" ]] && echo "🔍 Namespace used: $NAMESPACE"
[[ -n "$CONTEXT" ]] && echo "🧭 Context used: $CONTEXT"
