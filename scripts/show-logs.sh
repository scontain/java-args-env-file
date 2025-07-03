#!/usr/bin/env bash
set -euo pipefail

# Default values
NAMESPACE=""
JOB_NAME="java-cli-env-reader"

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Streams logs from the pod created by the Kubernetes Job: $JOB_NAME

Options:
  --namespace, -n <ns>   Kubernetes namespace (default: current context default)
  --help, -h             Show this help message

Examples:
  $0
  $0 -n my-namespace
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  --namespace | -n)
    NAMESPACE="$2"
    shift 2
    ;;
  --help | -h)
    print_help
    exit 0
    ;;
  *)
    echo "❌ Unknown argument: $1"
    print_help
    exit 1
    ;;
  esac
done

# Compose kubectl base command
KUBECTL="kubectl"
[[ -n "$NAMESPACE" ]] && KUBECTL+=" -n $NAMESPACE"

# Wait for Pod to be in Running or Succeeded state
echo "🔍 Looking for pod from job: $JOB_NAME..."
while true; do
  POD_NAME=$($KUBECTL get pods \
    --selector="app=$JOB_NAME" \
    --output=jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

  if [[ -n "$POD_NAME" ]]; then
    echo "✅ Found pod: $POD_NAME"
    break
  fi

  echo "⏳ Waiting for pod to start or complete..."
  sleep 1
done

# Stream logs from the Pod
echo "📜 Streaming logs from $POD_NAME..."
$KUBECTL logs "$POD_NAME" --follow || {
  echo "⚠️ Logs may be unavailable (e.g., if pod was evicted or deleted)"
  exit 1
}
