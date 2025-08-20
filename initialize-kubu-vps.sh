#!/bin/bash
# initialize-kubu-vps.sh
# KuBu VPS Initialization Script
# Downloads and deploys KuBu server configuration from private repository

set -euo pipefail

# Configuration
PRIVATE_REPO_URL="https://github.com/kunterbunt-edv/server-scripts"
PRIVATE_REPO_RAW="https://raw.githubusercontent.com/kunterbunt-edv/server-scripts/main"
MANAGEMENT_SCRIPT_PATH="/common/scripts/manage-kubu-vps.sh"
WORK_DIR="/tmp"
HOSTNAME=$(hostname)
TOKEN_FILE="$WORK_DIR/.${HOSTNAME}_token"
MANAGE_SCRIPT="$WORK_DIR/manage-kubu-vps.sh"
FINAL_TOKEN_DIR="/srv/tokens"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Welcome message
show_welcome() {
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}  VPS Server Initialization${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
    echo "This script will set up your VPS with the server configuration."
    echo ""
    echo "What will be installed:"
    echo "  • Server management scripts"
    echo "  • Docker project configurations" 
    echo "  • Welcome message and aliases"
    echo "  • Documentation and tools"
    echo ""
    read -p "Continue with initialization? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Initialization cancelled."
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in wget git curl; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Install missing tools:"
        echo "  sudo apt update"
        echo "  sudo apt install -y ${missing_tools[*]}"
        exit 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges"
        echo "Please ensure you can run sudo commands"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Guide user through GitHub token creation
create_github_token() {
    log_step "GitHub Token Setup"
    echo ""
    echo "To access the private repository, you need a GitHub token."
    echo ""
    echo -e "${YELLOW}IMPORTANT: Log in to GitHub with the admin account!${NC}"
    echo ""
    echo "1. Open this URL in your browser:"
    echo -e "   ${CYAN}https://github.com/settings/tokens${NC}"
    echo ""
    echo "2. Click 'Generate new token' → 'Generate new token (classic)'"
    echo ""
    echo "3. Configure the token:"
    echo "   • Name: 'VPS Management - $(hostname)'"
    echo "   • Expiration: 90 days (or as needed)"
    echo "   • Scopes: Check 'repo' (Full control of private repositories)"
    echo ""
    echo "4. Click 'Generate token'"
    echo ""
    echo "5. Copy the token (starts with 'ghp_')"
    echo "   ⚠️  You won't be able to see it again!"
    echo ""
    
    local token=""
    while [[ -z "$token" ]]; do
        read -p "Enter your GitHub token: " -r token
        
        if [[ -z "$token" ]]; then
            echo "Token cannot be empty. Please try again."
        elif [[ ! "$token" =~ ^ghp_ ]]; then
            log_warning "Token should start with 'ghp_' (classic token)"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                token=""
                continue
            fi
        fi
    done
    
    # Save token to file with hostname
    local hostname=$(hostname)
    TOKEN_FILE="$WORK_DIR/.${hostname}_token"
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    log_success "Token saved to $TOKEN_FILE"
    
    # Export for child processes
    export GITHUB_TOKEN="$token"
    
    return 0
}

# Download management script from private repository
download_management_script() {
    log_step "Downloading management script..."
    
    local token=$(cat "$TOKEN_FILE" | tr -d '\n\r ')
    local download_url="$PRIVATE_REPO_RAW$MANAGEMENT_SCRIPT_PATH"
    
    if wget --header="Authorization: token $token" \
            --output-document="$MANAGE_SCRIPT" \
            "$download_url"; then
        chmod +x "$MANAGE_SCRIPT"
        log_success "Management script downloaded to $MANAGE_SCRIPT"
        
        # Also save to /srv/scripts immediately
        sudo mkdir -p /srv/scripts
        sudo cp "$MANAGE_SCRIPT" /srv/scripts/
        sudo chmod +x /srv/scripts/manage-kubu-vps.sh
        log_success "Management script copied to /srv/scripts/"
        
        return 0
    else
        log_error "Failed to download management script"
        echo ""
        echo "Possible issues:"
        echo "  • Invalid GitHub token"
        echo "  • Token lacks 'repo' scope"
        echo "  • Network connectivity issues"
        echo "  • Repository URL changed"
        echo ""
        echo "Repository: $PRIVATE_REPO_URL"
        echo "Script path: $MANAGEMENT_SCRIPT_PATH"
        return 1
    fi
}

# Run deployment
run_deployment() {
    log_step "Ready for deployment"
    echo ""
    echo "The management script has been downloaded successfully."
    echo "Next step: Deploy the server configuration to your VPS."
    echo ""
    echo "This will:"
    echo "  • Clone the private repository temporarily"
    echo "  • Deploy scripts to /srv/scripts/"
    echo "  • Deploy Docker projects to /srv/docker/"
    echo "  • Install welcome message to /etc/profile.d/"
    echo "  • Set up all aliases and commands"
    echo ""
    
    read -p "Run deployment now? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Deployment skipped"
        echo ""
        echo "To run deployment later:"
        echo "  cd /srv/scripts"
        echo "  sudo GITHUB_TOKEN='$(cat $TOKEN_FILE)' ./manage-kubu-vps.sh --deploy"
        return 1
    fi
    
    # Change to work directory (where token file is located)
    cd "$WORK_DIR"
    
    log_info "Starting deployment..."
    
    # Pass token via environment variable
    if sudo GITHUB_TOKEN="$(cat $TOKEN_FILE)" "$MANAGE_SCRIPT" --deploy; then
        log_success "Deployment completed successfully!"
        return 0
    else
        log_error "Deployment failed"
        return 1
    fi
}

# Show welcome message after deployment
show_deployment_welcome() {
    log_step "Loading welcome message..."
    echo ""
    
    # Source the startup script to show welcome message immediately
    if [[ -f "/etc/profile.d/kubu-vps-startup.sh" ]]; then
        # Export functions and show welcome
        source /etc/profile.d/kubu-vps-startup.sh
        
        # Force show welcome message once
        if command -v show_welcome &>/dev/null; then
            show_welcome
        else
            log_info "Welcome function loaded - type 'welcome' to display"
        fi
    else
        log_warning "Welcome script not found - will be available after logout/login"
    fi
}

# Secure token and cleanup
finalize_setup() {
    log_step "Finalizing setup..."
    
    # Create secure token directory
    sudo mkdir -p "$FINAL_TOKEN_DIR"
    sudo chmod 700 "$FINAL_TOKEN_DIR"
    
    # Move token to secure location with hostname
    if [[ -f "$TOKEN_FILE" ]]; then
        local final_token_file="$FINAL_TOKEN_DIR/.${HOSTNAME}_token"
        sudo mv "$TOKEN_FILE" "$final_token_file"
        sudo chmod 600 "$final_token_file"
        log_success "Token moved to secure location: $final_token_file"
    fi
    
    # Clean up temporary files
    local cleanup_files=(
        "$WORK_DIR/initialize-kubu-vps.sh"
        "$MANAGE_SCRIPT"
    )
    
    for file in "${cleanup_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Cleaned up: $(basename "$file")"
        fi
    done
    
    log_success "Setup finalized and temporary files cleaned up"
}

# Show final instructions
show_final_instructions() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  VPS Setup Complete!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo "Your VPS is now configured with server management tools."
    echo ""
    echo -e "${CYAN}Available commands:${NC}"
    echo "  welcome          - Show server status and this information"
    echo "  install-docker   - Install Docker and Docker Compose"
    echo "  setup-groups     - Add current user to sudo and docker groups"
    echo "  manage-kubu-vps  - Main management tool"
    echo "  dockerdir        - Navigate to Docker projects"
    echo ""
    echo -e "${CYAN}Next recommended steps:${NC}"
    echo "1. Install Docker: install-docker"
    echo "2. Add user to groups: setup-groups"
    echo "3. Logout and login again to reload environment"
    echo "4. Check status: welcome"
    echo ""
    echo -e "${CYAN}Files and directories:${NC}"
    echo "  /srv/scripts/    - Management scripts"
    echo "  /srv/docker/     - Docker project configurations"
    echo "  /srv/docs/       - Documentation"
    echo "  /srv/tokens/     - Secure token storage"
    echo ""
    echo "For help: manage-kubu-vps --help"
    echo ""
}

# Handle errors
handle_error() {
    local exit_code=$?
    log_error "Initialization failed with exit code $exit_code"
    echo ""
    echo "Cleaning up temporary files..."
    
    # Clean up on error
    rm -f "$TOKEN_FILE" "$MANAGE_SCRIPT" "$WORK_DIR/initialize-kubu-vps.sh" 2>/dev/null
    
    echo ""
    echo "To try again:"
    echo "  wget https://raw.githubusercontent.com/kunterbunt-edv/server-scripts-public/main/initialize-kubu-vps.sh -O /tmp/initialize-kubu-vps.sh"
    echo "  chmod +x /tmp/initialize-kubu-vps.sh"
    echo "  /tmp/initialize-kubu-vps.sh"
    
    exit $exit_code
}

# Main execution
main() {
    # Set error handler
    trap handle_error ERR
    
    # Change to work directory
    cd "$WORK_DIR"
    
    # Run initialization steps
    show_welcome
    check_prerequisites
    create_github_token
    download_management_script
    
    if run_deployment; then
        show_deployment_welcome
        finalize_setup
        show_final_instructions
    else
        log_error "Deployment failed - keeping files for manual retry"
        echo ""
        echo "Manual deployment:"
        echo "  cd /srv/scripts"
        echo "  sudo GITHUB_TOKEN='$(cat $TOKEN_FILE 2>/dev/null || echo "YOUR_TOKEN")' ./manage-kubu-vps.sh --deploy"
        exit 1
    fi
    
    log_success "VPS initialization completed successfully!"
}

# Check if running as root (not recommended)
if [[ $EUID -eq 0 ]]; then
    log_warning "Running as root is not recommended"
    echo "Consider running as a regular user with sudo access"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Run main function
main "$@"
