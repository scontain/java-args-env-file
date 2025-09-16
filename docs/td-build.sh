#!/usr/bin/env bash
set -Eeuo pipefail

source ./docs/pe.sh

# -------- Scripted demo --------

pe '# Building the confidential application using the native container image'
pe '# and the native manifests.'
pe '# This is done with the helpf of scripts/td-build.sh'
pe '# - it takes the following arguments:'
pe './scripts/td-build.sh --help'
sleep 5 
pe '# We use the default repo and tag'
pe '# We use --permissive to allow to run on Kubernetes nodes with vulnerabilities'
./scripts/td-build.sh --permissive
sleep 5
pe '# The generated manifests are stored in generated/manifest.sanitized.yaml'
