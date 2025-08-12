#!/bin/bash

# Cyrus Proxy - Cloudflare Deployment Setup Script (macOS)
# This script creates all required KV namespaces and configures secrets

# Don't exit on error immediately - we'll handle errors manually
set +e

echo "========================================="
echo "Cyrus Proxy - Cloudflare Deployment Setup"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

# Enable debug mode if DEBUG=1 is set
if [ "${DEBUG:-0}" = "1" ]; then
    print_info "Debug mode enabled"
fi

# Check if wrangler is installed
print_info "Checking for Wrangler CLI..."
if ! command -v wrangler &> /dev/null; then
    print_error "Wrangler CLI is not installed or not in PATH"
    echo "Please run: pnpm install"
    exit 1
fi

WRANGLER_VERSION=$(wrangler --version 2>&1 | head -n 1)
print_success "Wrangler CLI found: $WRANGLER_VERSION"
echo ""

# Check if user is logged in to Cloudflare
print_info "Checking Cloudflare authentication..."
WHOAMI_OUTPUT=$(wrangler whoami 2>&1)
WHOAMI_EXIT_CODE=$?

if [ $WHOAMI_EXIT_CODE -ne 0 ]; then
    print_warning "Not logged in to Cloudflare"
    echo "Please authenticate with Cloudflare:"
    wrangler login
    
    # Check again after login
    WHOAMI_OUTPUT=$(wrangler whoami 2>&1)
    WHOAMI_EXIT_CODE=$?
    if [ $WHOAMI_EXIT_CODE -ne 0 ]; then
        print_error "Failed to authenticate with Cloudflare"
        exit 1
    fi
fi

# Extract account information
ACCOUNT_INFO=$(echo "$WHOAMI_OUTPUT" | grep -A 5 "Account")
print_success "Authenticated with Cloudflare"
echo "$ACCOUNT_INFO"
echo ""

# Prompt for Cloudflare Account ID
echo "========================================="
echo "Cloudflare Account Configuration"
echo "========================================="
echo ""

print_info "If you have multiple Cloudflare accounts, you need to specify which one to use."
print_info "You can find your Account ID in the output above or in the Cloudflare dashboard."
echo ""

read -p "Enter your Cloudflare Account ID (or press Enter to use default): " account_id_input
echo ""

if [ -n "$account_id_input" ]; then
    export CLOUDFLARE_ACCOUNT_ID="$account_id_input"
    print_success "Using Cloudflare Account ID: $CLOUDFLARE_ACCOUNT_ID"
    
    # Export the account ID for wrangler to use
    export CLOUDFLARE_ACCOUNT_ID
else
    print_info "Using default Cloudflare account"
fi
echo ""

# Function to list existing KV namespaces
list_existing_namespaces() {
    print_info "Checking for existing KV namespaces..."
    
    local list_output
    list_output=$(wrangler kv namespace list 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to list KV namespaces"
        print_debug "Output: $list_output"
        return 1
    fi
    
    echo "$list_output"
    return 0
}

# Function to extract namespace ID by title
get_namespace_id_by_title() {
    local title=$1
    local list_output=$2
    
    # Try to find the namespace by title and extract its ID
    # The output format is typically: { "id": "...", "title": "...", ... }
    local id=$(echo "$list_output" | grep -B 2 -A 2 "\"title\": \"$title\"" | grep "\"id\":" | head -1 | sed 's/.*"id": "\([^"]*\)".*/\1/')
    
    if [ -n "$id" ]; then
        echo "$id"
        return 0
    fi
    
    return 1
}

# Create or find KV namespaces
echo "========================================="
echo "Managing KV Namespaces"
echo "========================================="
echo ""

# Get list of existing namespaces
EXISTING_NAMESPACES=$(list_existing_namespaces)
if [ $? -eq 0 ]; then
    print_success "Retrieved list of existing KV namespaces"
    print_debug "Existing namespaces: $EXISTING_NAMESPACES"
else
    print_warning "Could not retrieve existing namespaces, will attempt to create new ones"
    EXISTING_NAMESPACES=""
fi
echo ""

# Array of namespaces to create
namespaces=("OAUTH_TOKENS" "OAUTH_STATE" "EDGE_TOKENS" "WORKSPACE_METADATA")

# Store namespace IDs (using parallel arrays for macOS compatibility)
namespace_ids=()
preview_namespace_ids=()

for i in "${!namespaces[@]}"; do
    namespace="${namespaces[$i]}"
    echo "----------------------------------------"
    echo "Processing namespace: $namespace"
    echo "----------------------------------------"
    
    # Check if production namespace already exists
    existing_id=""
    if [ -n "$EXISTING_NAMESPACES" ]; then
        # Try to find with the exact name
        existing_id=$(get_namespace_id_by_title "$namespace" "$EXISTING_NAMESPACES")
        if [ -n "$existing_id" ]; then
            print_success "Found existing production namespace $namespace with ID: $existing_id"
            namespace_ids[$i]=$existing_id
        else
            # Try with worker name prefix (e.g., "cyrus-proxy-OAUTH_TOKENS")
            existing_id=$(get_namespace_id_by_title "cyrus-proxy-$namespace" "$EXISTING_NAMESPACES")
            if [ -n "$existing_id" ]; then
                print_success "Found existing production namespace cyrus-proxy-$namespace with ID: $existing_id"
                namespace_ids[$i]=$existing_id
            fi
        fi
    fi
    
    # Create production namespace if it doesn't exist
    if [ -z "$existing_id" ]; then
        print_info "Creating new production namespace: $namespace"
        
        # Capture both stdout and stderr
        output=$(wrangler kv namespace create "$namespace" 2>&1)
        exit_code=$?
        
        print_debug "Exit code: $exit_code"
        print_debug "Output: $output"
        
        if [ $exit_code -eq 0 ]; then
            # Extract the ID from the output
            id=$(echo "$output" | grep -o 'id = "[^"]*"' | cut -d'"' -f2)
            if [ -n "$id" ]; then
                namespace_ids[$i]=$id
                print_success "Created production namespace $namespace with ID: $id"
            else
                print_error "Created namespace but couldn't extract ID"
                print_info "Output was: $output"
                namespace_ids[$i]=""
            fi
        else
            print_error "Failed to create production namespace $namespace"
            
            # Check for common error messages
            if echo "$output" | grep -q "already exists"; then
                print_warning "Namespace already exists but couldn't find it in the list"
                print_info "You may need to manually add the ID to wrangler.toml"
            elif echo "$output" | grep -q "unauthorized"; then
                print_error "Authorization failed - check your account ID and permissions"
            elif echo "$output" | grep -q "rate limit"; then
                print_error "Rate limited - wait a moment and try again"
            else
                print_info "Error output: $output"
            fi
            
            namespace_ids[$i]=""
            
            # Ask if user wants to continue
            read -p "Continue with other namespaces? (y/n): " continue_choice
            if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
                print_info "Exiting..."
                exit 1
            fi
        fi
    fi
    
    # Check for preview namespace
    echo ""
    existing_preview_id=""
    if [ -n "$EXISTING_NAMESPACES" ]; then
        # Try to find preview namespace
        existing_preview_id=$(get_namespace_id_by_title "${namespace}_preview" "$EXISTING_NAMESPACES")
        if [ -n "$existing_preview_id" ]; then
            print_success "Found existing preview namespace ${namespace}_preview with ID: $existing_preview_id"
            preview_namespace_ids[$i]=$existing_preview_id
        else
            # Try with worker name prefix
            existing_preview_id=$(get_namespace_id_by_title "cyrus-proxy-${namespace}_preview" "$EXISTING_NAMESPACES")
            if [ -n "$existing_preview_id" ]; then
                print_success "Found existing preview namespace cyrus-proxy-${namespace}_preview with ID: $existing_preview_id"
                preview_namespace_ids[$i]=$existing_preview_id
            fi
        fi
    fi
    
    # Create preview namespace if it doesn't exist
    if [ -z "$existing_preview_id" ]; then
        print_info "Creating new preview namespace: ${namespace}_preview"
        
        output=$(wrangler kv namespace create "$namespace" --preview 2>&1)
        exit_code=$?
        
        print_debug "Exit code: $exit_code"
        print_debug "Output: $output"
        
        if [ $exit_code -eq 0 ]; then
            # Extract the preview ID from the output
            preview_id=$(echo "$output" | grep -o 'preview_id = "[^"]*"' | cut -d'"' -f2)
            if [ -n "$preview_id" ]; then
                preview_namespace_ids[$i]=$preview_id
                print_success "Created preview namespace ${namespace}_preview with ID: $preview_id"
            else
                print_error "Created preview namespace but couldn't extract ID"
                print_info "Output was: $output"
                preview_namespace_ids[$i]=""
            fi
        else
            print_error "Failed to create preview namespace ${namespace}_preview"
            print_info "Error output: $output"
            preview_namespace_ids[$i]=""
        fi
    fi
    echo ""
done

# Generate wrangler.toml KV configuration
echo "========================================="
echo "Generating KV Configuration"
echo "========================================="
echo ""

kv_config=""
missing_namespaces=0

for i in "${!namespaces[@]}"; do
    namespace="${namespaces[$i]}"
    
    if [ -z "${namespace_ids[$i]}" ]; then
        print_warning "Missing production ID for $namespace"
        missing_namespaces=$((missing_namespaces + 1))
    fi
    
    kv_config+="[[kv_namespaces]]
binding = \"$namespace\"
id = \"${namespace_ids[$i]:-REPLACE_WITH_ACTUAL_ID}\"
preview_id = \"${preview_namespace_ids[$i]:-REPLACE_WITH_ACTUAL_PREVIEW_ID}\"

"
done

if [ $missing_namespaces -gt 0 ]; then
    print_warning "$missing_namespaces namespace(s) are missing IDs. You'll need to fill these in manually."
fi

echo "Add the following to your wrangler.toml file:"
echo ""
echo "$kv_config"

# Save to a file for reference
echo "$kv_config" > kv_namespaces.toml
print_success "KV namespace configuration saved to kv_namespaces.toml"
echo ""

# Ask if user wants to configure secrets
read -p "Do you want to configure secrets now? (y/n): " configure_secrets
if [ "$configure_secrets" != "y" ] && [ "$configure_secrets" != "Y" ]; then
    print_info "Skipping secret configuration"
    print_info "You can configure secrets later using: wrangler secret put SECRET_NAME"
    exit 0
fi

# Configure secrets
echo "========================================="
echo "Configuring Secrets"
echo "========================================="
echo ""

# Function to set a secret with better error handling
set_secret() {
    local secret_name=$1
    local prompt_text=$2
    local generate_if_empty=$3
    
    echo ""
    print_info "$prompt_text"
    
    if [ "$generate_if_empty" = "true" ]; then
        echo "Press Enter to generate a random value"
    fi
    
    read -s -p "Enter value for $secret_name: " secret_value
    echo ""
    
    if [ -z "$secret_value" ] && [ "$generate_if_empty" = "true" ]; then
        if [ "$secret_name" = "LINEAR_WEBHOOK_SECRET" ]; then
            secret_value=$(openssl rand -hex 32)
            print_success "Generated random webhook secret"
            echo "IMPORTANT: Save this webhook secret for Linear configuration:"
            echo "$secret_value"
            echo ""
        elif [ "$secret_name" = "ENCRYPTION_KEY" ]; then
            secret_value=$(openssl rand -hex 16)
            print_success "Generated random encryption key"
        fi
    fi
    
    if [ -n "$secret_value" ]; then
        print_info "Setting secret $secret_name..."
        output=$(echo "$secret_value" | wrangler secret put "$secret_name" 2>&1)
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            print_success "$secret_name configured successfully"
        else
            print_error "Failed to set $secret_name"
            print_debug "Error: $output"
            
            if echo "$output" | grep -q "already exists"; then
                print_info "Secret already exists. Use 'wrangler secret delete $secret_name' to remove it first."
            fi
        fi
    else
        print_warning "Skipped $secret_name - remember to set it before deploying"
    fi
}

print_info "You'll need the following from your Linear OAuth application:"
print_info "1. Client ID"
print_info "2. Client Secret"
print_info "3. A webhook secret (can be generated)"
print_info "4. An encryption key (can be generated)"
echo ""

# Linear OAuth Client ID
set_secret "LINEAR_CLIENT_ID" "Linear OAuth Client ID (from Linear API settings):" "false"

# Linear OAuth Client Secret
set_secret "LINEAR_CLIENT_SECRET" "Linear OAuth Client Secret (from Linear API settings):" "false"

# Linear Webhook Secret
set_secret "LINEAR_WEBHOOK_SECRET" "Linear Webhook Secret (leave empty to generate):" "true"

# Encryption Key
set_secret "ENCRYPTION_KEY" "Encryption Key (leave empty to generate):" "true"

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""

# Display summary
if [ $missing_namespaces -eq 0 ]; then
    print_success "All KV namespaces configured"
else
    print_warning "$missing_namespaces KV namespace(s) need manual configuration"
fi

print_success "Secrets configured (check for any warnings above)"
echo ""

echo "Next steps:"
echo "1. Update wrangler.toml with the KV namespace IDs from kv_namespaces.toml"
echo "2. Replace any REPLACE_WITH_ACTUAL_ID placeholders with actual IDs"
echo "3. Update the OAUTH_REDIRECT_URI in wrangler.toml with your worker URL"
echo "4. Deploy the worker with: pnpm deploy"
echo "5. Update your Linear OAuth application with:"
echo "   - Redirect URI: https://your-worker.workers.dev/oauth/callback"
echo "   - Webhook URL: https://your-worker.workers.dev/webhook"
echo "   - Webhook Secret: (use the one generated/provided above)"
echo ""

# Save configuration summary
cat > deployment-config.txt << EOF
Deployment Configuration Summary
================================
Generated: $(date)

Cloudflare Account ID: ${CLOUDFLARE_ACCOUNT_ID:-"(default)"}

KV Namespaces:
$(for i in "${!namespaces[@]}"; do
    if [ -n "${namespace_ids[$i]}" ]; then
        echo "✓ ${namespaces[$i]}: ${namespace_ids[$i]}"
    else
        echo "✗ ${namespaces[$i]}: NOT CREATED"
    fi
done)

Preview Namespaces:
$(for i in "${!namespaces[@]}"; do
    if [ -n "${preview_namespace_ids[$i]}" ]; then
        echo "✓ ${namespaces[$i]}_preview: ${preview_namespace_ids[$i]}"
    else
        echo "✗ ${namespaces[$i]}_preview: NOT CREATED"
    fi
done)

Secrets Configured:
- LINEAR_CLIENT_ID
- LINEAR_CLIENT_SECRET
- LINEAR_WEBHOOK_SECRET
- ENCRYPTION_KEY

Notes:
- Check the script output for any warnings or errors
- Ensure all REPLACE_WITH_ACTUAL_ID placeholders are replaced
- Save any generated secrets securely
EOF

print_success "Configuration summary saved to deployment-config.txt"
echo ""
print_warning "Keep deployment-config.txt secure and do not commit it to git!"

# Add files to .gitignore if they're not already there
if [ -f .gitignore ]; then
    if ! grep -q "deployment-config.txt" .gitignore; then
        echo "deployment-config.txt" >> .gitignore
        print_info "Added deployment-config.txt to .gitignore"
    fi
    if ! grep -q "kv_namespaces.toml" .gitignore; then
        echo "kv_namespaces.toml" >> .gitignore
        print_info "Added kv_namespaces.toml to .gitignore"
    fi
fi

print_info "Run with DEBUG=1 ./deploy-setup.sh for verbose output"