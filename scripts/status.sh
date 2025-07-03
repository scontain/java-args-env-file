#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=""
CONTEXT=""
HELP=false

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Displays status of Kubernetes resources created by the deployment.

Options:
  --namespace, -n <ns>   Kubernetes namespace (default: current context default)
  --context <ctx>        kubectl context to use
  --help                 Show this help message

Examples:
  $0
  $0 -n devspace
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

# Show resources related to the app
echo "📦 Checking status of Kubernetes resources..."
echo

echo "🔍 Jobs:"
$KUBECTL_CMD get jobs -o wide || true
echo

echo "🔍 Deployments:"
$KUBECTL_CMD get deployment -o wide || true
echo

echo "🔐 Secrets:"
$KUBECTL_CMD get secret || true
echo

echo "⚙️ ConfigMaps:"
$KUBECTL_CMD get configmap || true
echo

echo "📦 Pods:"
$KUBECTL_CMD get pods -o wide || true
echo

echo "📄 Events (last 20):"
$KUBECTL_CMD get events --sort-by='.metadata.creationTimestamp' | tail -n 20 || true
echo

echo "✅ Done"
[[ -n "$NAMESPACE" ]] && echo "📂 Namespace: $NAMESPACE"
[[ -n "$CONTEXT" ]] && echo "🧭 Context: $CONTEXT"
