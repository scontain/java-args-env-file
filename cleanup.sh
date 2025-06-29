#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=""
CONTEXT=""
HELP=false

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deletes all Kubernetes resources created from generated manifests.

Options:
  --namespace, -n <ns>   Target Kubernetes namespace (default: current context default)
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
    --namespace|-n)
      NAMESPACE="$2"
      shift 2
      ;;
    --context)
      CONTEXT="$2"
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

# Compose kubectl base command
KUBECTL_CMD="kubectl"
[[ -n "$CONTEXT" ]] && KUBECTL_CMD+=" --context=$CONTEXT"
[[ -n "$NAMESPACE" ]] && KUBECTL_CMD+=" --namespace=$NAMESPACE"

# Clean up all generated .yaml files
for file in *.yaml; do
  if [[ "$file" =~ \.template\.yaml$ ]]; then
    continue
  fi
  echo "🗑️ Deleting resources from $file"
  $KUBECTL_CMD delete -f "$file" --ignore-not-found
done

echo "✅ Cleanup complete"
[[ -n "$NAMESPACE" ]] && echo "🔍 Namespace used: $NAMESPACE"
[[ -n "$CONTEXT" ]] && echo "🧭 Context used: $CONTEXT"

