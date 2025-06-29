#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=""
SECRET_NAME="java-cli-env-secret"

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Retrieve and base64 decode Kubernetes secrets "password" and "my_db_encryption_key"

Options:
  --namespace, -n <ns>    Kubernetes namespace (default: current context default)
  --secret <name>         Kubernetes secret name (default: java-cli-env-secret)
  --help, -h              Show this help message
EOF
}

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n)
      NAMESPACE="$2"
      shift 2
      ;;
    --secret)
      SECRET_NAME="$2"
      shift 2
      ;;
    --help|-h)
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

KUBECTL="kubectl"
[[ -n "$NAMESPACE" ]] && KUBECTL+=" -n $NAMESPACE"

KEYS=("secrets")

for key in "${KEYS[@]}"; do
  echo "🔑 Secret key: $key"

  encoded=$($KUBECTL get secret "$SECRET_NAME" -o "jsonpath={.data.$key}" 2>/dev/null || true)
  if [[ -z "$encoded" ]]; then
    echo "⚠️  Key '$key' not found in secret '$SECRET_NAME' or secret does not exist."
    echo
    continue
  fi

  echo "Encoded (base64):"
  echo "$encoded"

  # Always decode base64
  if decoded=$(echo "$encoded" | base64 --decode 2>/dev/null); then
    echo "Decoded:"
    echo "$decoded"
  else
    echo "❌ Failed to decode base64 value"
  fi
  echo
done
