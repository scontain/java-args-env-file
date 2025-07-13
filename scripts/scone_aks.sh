#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CREATE_CLUSTER=true
INSTALL_OPERATOR=false
DELETE_CLUSTER=false
FORCE=false

# Credential variables (can be set via env or flags)
REGISTRY_USERNAME=${REGISTRY_USERNAME:-""}
REGISTRY_ACCESS_TOKEN=${REGISTRY_ACCESS_TOKEN:-""}
REGISTRY_EMAIL=${REGISTRY_EMAIL:-""}
GROUP_AKS=${GROUP_AKS:-""}
DCAP_API_KEY=${DCAP_API_KEY:-"aecd5ebb682346028d60c36131eb2d92"}  # Default value
CZ=3

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nocluster)
            CREATE_CLUSTER=false
            shift
            ;;
        --operator)
            INSTALL_OPERATOR=true
            shift
            ;;
        --delete)
            DELETE_CLUSTER=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --registry-username)
            REGISTRY_USERNAME="$2"
            shift 2
            ;;
        --registry-token)
            REGISTRY_ACCESS_TOKEN="$2"
            shift 2
            ;;
        --registry-email)
            REGISTRY_EMAIL="$2"
            shift 2
            ;;
        --resource-group)
            GROUP_AKS="$2"
            shift 2
            ;;
        --dcap-key)
            DCAP_API_KEY="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown argument: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

show_help() {
    echo -e "${GREEN}Usage: $0 [OPTIONS]${NC}"
    echo -e "Options:"
    echo -e "  --nocluster             Skip cluster creation"
    echo -e "  --operator              Install SCONE operator"
    echo -e "  --delete                Delete the AKS cluster (ignores other flags)"
    echo -e "  --force                 Skip confirmation prompts"
    echo -e "  --registry-username     Registry username (or set REGISTRY_USERNAME env)"
    echo -e "  --registry-token        Registry access token (or set REGISTRY_ACCESS_TOKEN env)"
    echo -e "  --registry-email        Registry email (or set REGISTRY_EMAIL env)"
    echo -e "  --resource-group        Azure resource group (or set GROUP_AKS env)"
    echo -e "  --dcap-key              DCAP API key (or set DCAP_API_KEY env)"
    echo -e "  --help                  Show this help message"
    echo -e ""
    echo -e "Note: All credentials can be provided either via flags or environment variables."
}

# Enhanced error handling
trap 'echo -e "${RED}⛔ Script failed at line $LINENO. Command: $BASH_COMMAND${NC}"; exit 1' ERR

# Check if already logged in to Azure
check_azure_login() {
    echo -e "${GREEN}🔍 Checking Azure login status...${NC}"
    if az account show &>/dev/null; then
        echo -e "${GREEN}✅ Already logged in to Azure${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ Not logged in to Azure${NC}"
        return 1
    fi
}

# Check if cluster already exists
cluster_exists() {
    echo -e "${GREEN}🔍 Checking if cluster 'aks-scone' exists in resource group '$GROUP_AKS'...${NC}"
    if az aks show --name aks-scone --resource-group "$GROUP_AKS" &>/dev/null; then
        echo -e "${YELLOW}⚠️ Cluster 'aks-scone' already exists in resource group '$GROUP_AKS'${NC}"
        return 0
    else
        echo -e "${GREEN}✅ Cluster 'aks-scone' does not exist in resource group '$GROUP_AKS'${NC}"
        return 1
    fi
}

# Delete AKS cluster
delete_aks_cluster() {
    if [[ -z "$GROUP_AKS" ]]; then
        echo -e "${RED}❌ Resource group (--resource-group or GROUP_AKS) must be specified for deletion${NC}"
        exit 1
    fi

    if ! cluster_exists; then
        echo -e "${RED}❌ Cluster 'aks-scone' does not exist in resource group '$GROUP_AKS'${NC}"
        exit 1
    fi

    if [ "$FORCE" = false ]; then
        echo -e "${YELLOW}⚠️ WARNING: You are about to delete the AKS cluster 'aks-scone' in resource group '$GROUP_AKS'${NC}"
        read -p "Are you sure you want to continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✅ Cluster deletion canceled${NC}"
            exit 0
        fi
    fi

    if ! check_azure_login; then
        echo -e "${GREEN}🚀 Logging in to Azure...${NC}"
        if ! az login --use-device-code; then
            echo -e "${RED}❌ Failed to log in to Azure${NC}"
            exit 1
        fi
    fi

    echo -e "${RED}🔥 Deleting AKS cluster...${NC}"
    if ! az aks delete --name aks-scone --resource-group "$GROUP_AKS" --yes --no-wait; then
        echo -e "${RED}❌ Failed to delete AKS cluster${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ AKS cluster deletion initiated. It may take some time to complete.${NC}"
    echo -e "${YELLOW}ℹ️ Note: The --no-wait flag means deletion happens asynchronously.${NC}"
    echo -e "${YELLOW}You can check status with: az aks show --name aks-scone --resource-group $GROUP_AKS${NC}"
    exit 0
}

# Check if Azure CLI is installed
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed. Please install it first.${NC}"
        echo -e "${YELLOW}👉 Installation guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Azure CLI is installed${NC}"
}

# Check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl is not installed. Please install it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ kubectl is installed${NC}"
}

# Check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq is not installed. Please install it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ jq is installed${NC}"
}

# Check required credentials
check_credentials() {
    local missing=()
    
    # Check registry credentials (only if operator will be installed)
    if [ "$INSTALL_OPERATOR" = true ]; then
        [[ -z "$REGISTRY_USERNAME" ]] && missing+=("Registry username (--registry-username or REGISTRY_USERNAME)")
        [[ -z "$REGISTRY_ACCESS_TOKEN" ]] && missing+=("Registry token (--registry-token or REGISTRY_ACCESS_TOKEN)")
        [[ -z "$REGISTRY_EMAIL" ]] && missing+=("Registry email (--registry-email or REGISTRY_EMAIL)")
        [[ -z "$DCAP_API_KEY" ]] && missing+=("DCAP API key (--dcap-key or DCAP_API_KEY)")
    fi

    # Check AKS resource group (only if cluster will be created)
    if [ "$CREATE_CLUSTER" = true ]; then
        [[ -z "$GROUP_AKS" ]] && missing+=("Resource group (--resource-group or GROUP_AKS)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing required credentials:${NC}"
        for item in "${missing[@]}"; do
            echo -e "${YELLOW}  - $item${NC}"
        done
        echo -e ""
        echo -e "${YELLOW}Either provide these via command line flags or set them as environment variables.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ All required credentials are available${NC}"
}

# Create AKS cluster with error handling
create_aks_cluster() {
    if ! check_azure_login; then
        echo -e "${GREEN}🚀 Logging in to Azure...${NC}"
        if ! az login --use-device-code; then
            echo -e "${RED}❌ Failed to log in to Azure${NC}"
            exit 1
        fi
    fi

    if cluster_exists; then
        if [ "$FORCE" = false ]; then
            echo -e "${YELLOW}⚠️ Cluster 'aks-scone' already exists in resource group '$GROUP_AKS'${NC}"
            read -p "Do you want to recreate it? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}✅ Using existing cluster${NC}"
                return
            fi
        fi

        echo -e "${YELLOW}⚠️ Deleting existing cluster before recreation...${NC}"
        if ! az aks delete --name aks-scone --resource-group "$GROUP_AKS" --yes --no-wait; then
            echo -e "${RED}❌ Failed to delete existing cluster${NC}"
            exit 1
        fi

        # Wait for cluster to be deleted
        echo -e "${YELLOW}⏳ Waiting for existing cluster to be deleted...${NC}"
        while cluster_exists; do
            sleep 10
        done
    fi

    echo -e "${GREEN}🏗️ Creating AKS cluster...${NC}"
    if ! az aks create --name aks-scone --generate-ssh-keys --enable-addons confcom \
        -c $CZ --node-vm-size Standard_DC4s_v3 -g "$GROUP_AKS" --node-osdisk-size 64; then
        echo -e "${RED}❌ Failed to create AKS cluster${NC}"
        exit 1
    fi

    echo -e "${GREEN}🔧 Getting cluster credentials...${NC}"
    if ! az aks get-credentials --name aks-scone --resource-group "$GROUP_AKS" \
        --file ~/.kube/config --overwrite-existing; then
        echo -e "${RED}❌ Failed to get cluster credentials${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ AKS cluster setup complete!${NC}"
}

# Install SCONE Operator with error handling
install_operator() {
    echo -e "${GREEN}⚙️ Installing SCONE Operator and plugins...${NC}"
    if ! curl -fsSL https://raw.githubusercontent.com/scontain/SH/master/5.9.0/operator_controller | bash -s - \
        --set-version 5.9.0 --plugin --reconcile --update --secret-operator --verbose \
        --username "$REGISTRY_USERNAME" --access-token "$REGISTRY_ACCESS_TOKEN" \
        --email "$REGISTRY_EMAIL" --dcap-api "$DCAP_API_KEY"; then
        echo -e "${RED}❌ Failed to install SCONE Operator${NC}"
        exit 1
    fi

    pause_if_slow

    wait_for_resource_ready() {
        local kind="$1"
        local name="$2"
        local namespace="$3"
        local attempts=0
        local max_attempts=20
        
        echo -e "${YELLOW}⏳ Waiting for $kind/$name in $namespace to be ready...${NC}"
        while true; do
            ready=$(kubectl get "$kind" "$name" -n "$namespace" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "")
            total=$(kubectl get "$kind" "$name" -n "$namespace" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "")
            
            if [[ "$ready" == "$total" && -n "$ready" ]]; then
                break
            fi
            
            attempts=$((attempts+1))
            if [ $attempts -ge $max_attempts ]; then
                echo -e "${RED}❌ Timed out waiting for $kind/$name to be ready${NC}"
                exit 1
            fi
            sleep 3
        done
        echo -e "${GREEN}✅ $kind/$name is ready${NC}"
    }

    wait_for_cas_healthy() {
        local attempts=0
        local max_attempts=50
        
        echo -e "${YELLOW}⏳ Waiting for CAS to be HEALTHY, PROVISIONED and MIGRATION $CZ/$CZ...${NC}"
        while true; do
            output=$(kubectl get cas cas -n scone-system -o json 2>/dev/null || echo "")
            phase=$(echo "$output" | jq -r '.status.phase // empty')
            provisioned=$(echo "$output" | jq -r '.status.provisioned // "No"')

            if [[ "$phase" == "HEALTHY" && "$provisioned" == "Yes" ]]; then
                break
            fi
            
            attempts=$((attempts+1))
            if [ $attempts -ge $max_attempts ]; then
                echo -e "${RED}❌ Timed out waiting for CAS to be ready${NC}"
                exit 1
            fi
            sleep 10
        done
        echo -e "${GREEN}✅ CAS is HEALTHY, PROVISIONED and MIGRATION is $CZ/$CZ${NC}"
    }

    wait_for_resource_ready daemonset las scone-system || exit 1
    wait_for_resource_ready daemonset sgxplugin scone-system || exit 1

    echo -e "${GREEN}🔐 Provisioning CAS...${NC}"
    if ! kubectl provision cas cas -n scone-system --no-image-signature-check; then
        echo -e "${RED}❌ Failed to provision CAS${NC}"
        exit 1
    fi

    wait_for_cas_healthy || exit 1
}

# Pause function if running in slow environment
pause_if_slow() {
    echo -e "${YELLOW}⏳ Pausing for 30 seconds to allow resources to stabilize...${NC}"
    sleep 30
}

# Main execution
main() {
    # Check if delete flag was set
    if [ "$DELETE_CLUSTER" = true ]; then
        delete_aks_cluster
        # delete_aks_cluster will exit the script, so we don't need to worry about other operations
    fi

    # Check dependencies
    check_azure_cli
    check_kubectl
    check_jq
    check_credentials

    # Create cluster if requested
    if [ "$CREATE_CLUSTER" = true ]; then
        create_aks_cluster
    else
        echo -e "${YELLOW}⚠️ Skipping cluster creation (--nocluster specified)${NC}"
    fi

    # Install operator if requested
    if [ "$INSTALL_OPERATOR" = true ]; then
        install_operator
    else
        echo -e "${YELLOW}⚠️ Skipping operator installation (--operator not specified)${NC}"
    fi

    echo -e "${GREEN}🎉 All operations completed successfully!${NC}"
}

# Run main function
main
