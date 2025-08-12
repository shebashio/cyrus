#!/bin/bash

# Cyrus Proxy - Deployment Cleanup Script
# This script removes temporary files created by deploy-setup.sh

echo "========================================="
echo "Cyrus Proxy - Deployment Cleanup"
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

# Files to clean up
files_to_remove=(
    "kv_namespaces.toml"
    "deployment-config.txt"
)

# Check if wrangler.toml has been updated
print_info "Checking if wrangler.toml has KV namespaces configured..."

if [ -f "wrangler.toml" ]; then
    if grep -q "^\[\[kv_namespaces\]\]" wrangler.toml; then
        print_success "Found KV namespace configuration in wrangler.toml"
        
        # Count configured namespaces
        namespace_count=$(grep -c "^binding = " wrangler.toml || true)
        print_info "Found $namespace_count KV namespace bindings"
        
        if [ $namespace_count -lt 4 ]; then
            print_warning "Expected 4 namespaces (OAUTH_TOKENS, OAUTH_STATE, EDGE_TOKENS, WORKSPACE_METADATA)"
            print_warning "Only found $namespace_count - make sure all are configured before cleaning up"
            
            read -p "Continue with cleanup anyway? (y/n): " continue_choice
            if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
                print_info "Cleanup cancelled"
                exit 0
            fi
        fi
    else
        print_warning "No KV namespace configuration found in wrangler.toml"
        print_info "Make sure you've added the KV namespace configuration before running cleanup"
        
        read -p "Continue with cleanup anyway? (y/n): " continue_choice
        if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
            print_info "Cleanup cancelled"
            exit 0
        fi
    fi
else
    print_error "wrangler.toml not found"
    exit 1
fi

echo ""
echo "========================================="
echo "Removing Temporary Files"
echo "========================================="
echo ""

# Remove each file
removed_count=0
for file in "${files_to_remove[@]}"; do
    if [ -f "$file" ]; then
        rm "$file"
        print_success "Removed $file"
        removed_count=$((removed_count + 1))
    else
        print_info "$file not found (already removed or not created)"
    fi
done

echo ""

# Check for any backup files
backup_files=$(ls *.backup 2>/dev/null | wc -l)
if [ $backup_files -gt 0 ]; then
    print_warning "Found $backup_files backup file(s)"
    read -p "Remove backup files too? (y/n): " remove_backups
    if [ "$remove_backups" = "y" ] || [ "$remove_backups" = "Y" ]; then
        rm *.backup
        print_success "Removed backup files"
    else
        print_info "Keeping backup files"
    fi
fi

# Summary
echo "========================================="
echo "Cleanup Complete"
echo "========================================="
echo ""

if [ $removed_count -gt 0 ]; then
    print_success "Removed $removed_count temporary file(s)"
else
    print_info "No temporary files to remove"
fi

echo ""
print_info "Next steps:"
echo "1. Deploy your worker with: pnpm deploy"
echo "2. Test the deployment at your worker URL"
echo "3. Configure Linear OAuth application with your worker URLs"

# Final check for secrets
echo ""
print_info "Checking if secrets are configured..."

# List secrets (this will show if they exist, not their values)
secrets_output=$(wrangler secret list 2>&1)
if echo "$secrets_output" | grep -q "LINEAR_CLIENT_ID\|LINEAR_CLIENT_SECRET\|LINEAR_WEBHOOK_SECRET\|ENCRYPTION_KEY"; then
    print_success "Found configured secrets"
else
    print_warning "Some secrets may not be configured"
    print_info "Use 'wrangler secret list' to check configured secrets"
    print_info "Use 'wrangler secret put SECRET_NAME' to add missing secrets"
fi

echo ""
print_success "Ready to deploy!"
print_info "Run: pnpm deploy"