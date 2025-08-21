#!/bin/bash
# initialize-kubu-vps.sh
# KuBu VPS Initialization Script with improved token management
# Downloads and deploys KuBu server configuration from private repository
# Repository: server-scripts-public/
# Dependencies: wget, git, curl, sudo access

set -euo pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_PREREQUISITES=1
readonly EXIT_TOKEN_INVALID=2
readonly EXIT_DOWNLOAD_FAILED=3
readonly EXIT_DEPLOYMENT_FAILED=4
readonly EXIT_USER_CANCELLED=5

# Configuration
readonly PRIVATE_REPO_URL="https://github.com/kunterbunt-edv/server-scripts"
readonly PRIVATE_REPO_RAW="https://raw.githubusercontent.com/kunterbunt-edv/server-scripts/main"
readonly MANAGEMENT_SCRIPT_PATH="/common/scripts/manage-kubu-vps.sh"
readonly WORK_DIR="/tmp"
readonly REPO_NAME="server-scripts"  # Extract repo name for token naming
readonly TOKEN_FILE="$WORK_DIR/.${REPO_NAME}_token"
readonly SECURE_TOKEN_DIR="/srv/tokens"
readonly SECURE_TOKEN_FILE="$SECURE_TOKEN_DIR/.${REPO_NAME}_token"
readonly MANAGE_SCRIPT="$WORK_DIR/manage-kubu-vps.sh"

# Color definitions with semantic meaning
readonly COLOR_ERROR='\033[0;31m'        # Red - Errors and critical issues
readonly COLOR_SUCCESS='\033[0;32m'      # Green - Successful operations
readonly COLOR_WARNING='\033[0;33m'      # Yellow - Warnings and cautions
readonly COLOR_INFO='\033[0;34m'         # Blue - Informational messages
readonly COLOR_STEP='\033[0;35m'         # Purple - Process steps
readonly COLOR_HIGHLIGHT='\033[0;36m'    # Cyan - Highlighting important items
readonly COLOR_RESET='\033[0m'           # Reset all formatting

# Legacy aliases for compatibility
readonly RED=$COLOR_ERROR
readonly GREEN=$COLOR_SUCCESS
readonly YELLOW=$COLOR_WARNING
readonly BLUE=$COLOR_INFO
readonly PURPLE=$COLOR_STEP
readonly CYAN=$COLOR_HIGHLIGHT
readonly NC=$COLOR_RESET

# Logging functions
log_info() { echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $1"; }
log_success() { echo -e "${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $1"; }
log_warning() { echo -e "${COLOR_WARNING}[WARNING]${COLOR_RESET} $1"; }
log_error() { echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $1"; }
log_step() { echo -e "${COLOR_STEP}[STEP]${COLOR_RESET} $1"; }

# User input helper - consolidated function for all y/N prompts
ask_continue() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"  # n=default no, y=default yes
    
    if [[ "$default" == "y" ]]; then
        read -p "$prompt (Y/n): " -n 1 -r
        echo
        [[ -z "$REPLY" || "$REPLY" =~ ^[Yy]$ ]]
    else
        read -p "$prompt (y/N): " -n 1 -r
        echo
        [[ "$REPLY" =~ ^[Yy]$ ]]
    fi
}

# Cleanup helper functions
cleanup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_info "Cleaned up: $(basename "$file")"
    fi
}

cleanup_files() {
    local files=("$@")
    for file in "${files[@]}"; do
        cleanup_file "$file"
    done
}

# Welcome message
show_welcome() {
    echo -e "${COLOR_HIGHLIGHT}================================================${COLOR_RESET}"
    echo -e "${COLOR_HIGHLIGHT}  KuBu VPS Server Initialization${COLOR_RESET}"
    echo -e "${COLOR_HIGHLIGHT}================================================${COLOR_RESET}"
    echo ""
    echo "This script will set up your VPS with the KuBu server configuration."
    echo ""
    echo "What will be installed:"
    echo "  • Server management scripts"
    echo "  • Docker project configurations" 
    echo "  • Welcome message and aliases"
    echo "  • Documentation and tools"
    echo ""
    
    if ! ask_continue "Continue with initialization?"; then
        echo "Initialization cancelled."
        exit $EXIT_USER_CANCELLED
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
        exit $EXIT_PREREQUISITES
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges"
        echo "Please ensure you can run sudo commands"
        exit $EXIT_PREREQUISITES
    fi
    
    log_success "Prerequisites check passed"
}

# Show token creation guide
show_token_creation_guide() {
    echo ""
    echo -e "${COLOR_WARNING}=== GitHub Token Creation Guide ===${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_WARNING}IMPORTANT: Log in to GitHub with the admin account!${COLOR_RESET}"
    echo ""
    echo "1. Open this URL in your browser:"
    echo -e "   ${COLOR_HIGHLIGHT}https://github.com/settings/tokens${COLOR_RESET}"
    echo ""
    echo "2. Click 'Generate new token' → 'Generate new token (classic)'"
    echo ""
    echo "3. Configure the token:"
    echo "   • Name: 'KuBu VPS Management - $REPO_NAME'"
    echo "   • Expiration: 90 days (or as needed)"
    echo "   • Scopes: Check 'repo' (Full control of private repositories)"
    echo ""
    echo "4. Click 'Generate token'"
    echo ""
    echo "5. Copy the token (starts with 'ghp_')"
    echo "   ⚠️  You won't be able to see it again!"
    echo ""
}

# Find existing token - consolidated token search logic
find_token() {
    # Priority order for token discovery:
    # 1. Secure location (/srv/tokens/)
    # 2. Working directory
    # 3. Script directory
    # 4. Temporary directory
    
    local token_files=(".${REPO_NAME}_token" ".kubu-token")
    local search_paths=("$SECURE_TOKEN_DIR" "." "$WORK_DIR")
    
    for token_file in "${token_files[@]}"; do
        for search_path in "${search_paths[@]}"; do
            local full_path="$search_path/$token_file"
            if [[ -f "$full_path" ]]; then
                local token_content=$(cat "$full_path" 2>/dev/null | tr -d '\n\r ')
                if [[ -n "$token_content" ]]; then
                    echo "$token_content"
                    return 0
                fi
            fi
        done
    done
    
    return 1
}

# Check for existing token first - separate function
check_existing_token() {
    # Purpose: Check for existing GitHub token and offer reuse options
    # Returns: 0 if token found and valid, 1 if new token needed
    # Side effects: Sets GITHUB_TOKEN environment variable
    
    log_step "Checking for existing GitHub token..."
    
    # Check for existing token in secure location
    if [[ -f "$SECURE_TOKEN_FILE" ]]; then
        local existing_token=$(cat "$SECURE_TOKEN_FILE" 2>/dev/null | tr -d '\n\r ')
        if [[ -n "$existing_token" ]]; then
            log_info "Found existing GitHub token: $SECURE_TOKEN_FILE"
            echo ""
            echo "Options:"
            echo "1) Use existing token"
            echo "2) Enter new token"
            echo "3) Show token creation guide"
            echo ""
            read -p "Choose option (1/2/3): " -n 1 -r
            echo ""
            
            case "$REPLY" in
                "1"|"")
                    log_info "Using existing token"
                    cp "$SECURE_TOKEN_FILE" "$TOKEN_FILE"
                    chmod 600 "$TOKEN_FILE"
                    export GITHUB_TOKEN="$existing_token"
                    log_success "Using existing GitHub token"
                    return 0
                    ;;
                "2")
                    log_info "Will create new token..."
                    return 1  # Continue to token creation
                    ;;
                "3")
                    show_token_creation_guide
                    return 1  # Continue to token creation
                    ;;
                *)
                    log_info "Invalid choice, using existing token"
                    cp "$SECURE_TOKEN_FILE" "$TOKEN_FILE"
                    chmod 600 "$TOKEN_FILE"
                    export GITHUB_TOKEN="$existing_token"
                    log_success "Using existing GitHub token"
                    return 0
                    ;;
            esac
        fi
    fi
    
    # No existing token found
    log_info "No existing token found, need to create one"
    return 1
}

# Create new GitHub token
create_github_token() {
    show_token_creation_guide
    
    local token=""
    while [[ -z "$token" ]]; do
        echo ""
        echo "Enter your GitHub token (starts with 'ghp_'):"
        echo -n "Token: "
        
        # Temporarily disable set -u for input to avoid issues
        set +u
        read token
        set -u
        
        if [[ -z "$token" ]]; then
            echo "Token cannot be empty. Please try again."
        elif [[ ! "$token" =~ ^ghp_ ]]; then
            log_warning "Token should start with 'ghp_' (classic token)"
            if ! ask_continue "Continue anyway?"; then
                token=""
                continue
            fi
        fi
    done
    
    # Save token to temporary file
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    log_success "Token saved temporarily to $TOKEN_FILE"
    
    # Also save to secure location immediately
    sudo mkdir -p "$SECURE_TOKEN_DIR"
    sudo chmod 700 "$SECURE_TOKEN_DIR"
    sudo cp "$TOKEN_FILE" "$SECURE_TOKEN_FILE"
    sudo chmod 600 "$SECURE_TOKEN_FILE"
    log_success "Token also saved to secure location: $SECURE_TOKEN_FILE"
    
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

# Test token before deployment
test_github_token() {
    log_step "Testing GitHub token..."
    
    local token=$(cat "$TOKEN_FILE" | tr -d '\n\r ')
    local test_url="$PRIVATE_REPO_RAW/README.md"
    
    if wget --spider --header="Authorization: token $token" "$test_url" 2>/dev/null; then
        log_success "GitHub token is valid and has repository access"
        return 0
    else
        log_error "GitHub token test failed"
        echo ""
        echo "The token might be:"
        echo "  • Invalid or expired"
        echo "  • Missing 'repo' scope"
        echo "  • Not authorized for this repository"
        echo ""
        if ask_continue "Try with a different token?"; then
            # Remove failed token and try again
            rm -f "$TOKEN_FILE" "$SECURE_TOKEN_FILE" 2>/dev/null
            return 1  # Signal to retry token creation
        else
            return 1
        fi
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
    
    if ! ask_continue "Run deployment now?" "y"; then
        log_info "Deployment skipped"
        echo ""
        echo "To run deployment later:"
        echo "  cd /srv/scripts"
        echo "  sudo GITHUB_TOKEN='$(cat $TOKEN_FILE 2>/dev/null || echo "YOUR_TOKEN")' ./manage-kubu-vps.sh deploy --force"
        return 1
    fi
    
    # Change to work directory (where token file is located)
    cd "$WORK_DIR"
    
    log_info "Starting deployment..."
    
    # Pass token via environment variable and use --force to skip confirmations
    if sudo GITHUB_TOKEN="$(cat $TOKEN_FILE)" /bin/bash "$MANAGE_SCRIPT" deploy --force; then
        log_success "Deployment completed successfully!"
        return 0
    else
        log_error "Deployment failed"
        return 1
    fi
}

# Show welcome message after deployment - no automatic welcome
show_deployment_welcome() {
    # Just confirm the script is ready, don't load it yet
    if [[ -f "/etc/profile.d/kubu-vps-startup.sh" ]]; then
        log_success "Welcome script deployed successfully"
    else
        log_warning "Welcome script not found - will be available after logout/login"
    fi
}

# Secure token and cleanup
finalize_setup() {
    log_step "Finalizing setup..."
    
    # Token is already in secure location from create_github_token()
    if [[ -f "$SECURE_TOKEN_FILE" ]]; then
        log_success "Token secured at: $SECURE_TOKEN_FILE"
    fi
    
    # Clean up temporary files using helper function
    local cleanup_targets=(
        "$WORK_DIR/initialize-kubu-vps.sh"
        "$MANAGE_SCRIPT"
        "$TOKEN_FILE"  # Remove temporary token file
    )
    
    cleanup_files "${cleanup_targets[@]}"
    
    log_success "Setup finalized and temporary files cleaned up"
}

# Show final instructions
show_final_instructions() {
    echo ""
    echo -e "${COLOR_SUCCESS}================================================${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}  KuBu VPS Setup Complete!${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}================================================${COLOR_RESET}"
    echo ""
    echo "Your VPS is now configured with KuBu server management tools."
    echo ""
    echo -e "${COLOR_HIGHLIGHT}Available commands:${COLOR_RESET}"
    echo "  welcome          - Show server status and information"
    echo "  install-docker   - Install Docker and Docker Compose"
    echo "  setup-groups     - Add current user to sudo and docker groups"
    echo "  manage-kubu-vps  - Main management tool"
    echo "  dockerdir        - Navigate to Docker projects"
    echo ""
    echo -e "${COLOR_HIGHLIGHT}Next recommended steps:${COLOR_RESET}"
    echo "1. Install Docker: install-docker"
    echo "2. Add user to groups: setup-groups"
    echo "3. Logout and login again to reload environment"
    echo "4. Check status: welcome"
    echo ""
    echo -e "${COLOR_HIGHLIGHT}Files and directories:${COLOR_RESET}"
    echo "  /srv/scripts/    - Management scripts"
    echo "  /srv/docker/     - Docker project configurations"
    echo "  /srv/docs/       - Documentation"
    echo "  /srv/tokens/     - Secure token storage"
    echo ""
    echo "For help: manage-kubu-vps --help"
    echo ""
    echo -e "${COLOR_WARNING}Token Management:${COLOR_RESET}"
    echo "Your GitHub token is securely stored in $SECURE_TOKEN_DIR"
    echo "Future deployments will automatically use this token."
    echo ""
}

# Handle errors - improved cleanup function
handle_error() {
    local exit_code=$?
    log_error "Initialization failed with exit code $exit_code"
    echo ""
    echo "Cleaning up temporary files..."
    
    # Clean up on error but keep secure token if it was created
    cleanup_files "$TOKEN_FILE" "$MANAGE_SCRIPT" "$WORK_DIR/initialize-kubu-vps.sh"
    
    echo ""
    echo "To try again:"
    echo "  wget https://raw.githubusercontent.com/kunterbunt-edv/server-scripts-public/main/initialize-kubu-vps.sh -O /tmp/initialize-kubu-vps.sh"
    echo "  chmod +x /tmp/initialize-kubu-vps.sh"
    echo "  /tmp/initialize-kubu-vps.sh"
    
    exit $exit_code
}

# Main execution - corrected flow
main() {
    # Set error handler
    trap handle_error ERR
    
    # Change to work directory
    cd "$WORK_DIR"
    
    # Run initialization steps
    show_welcome
    check_prerequisites
    
    # Token handling
    local token_ready=false
    local token_attempts=0
    local max_attempts=3
    
    # First check if token already exists
    if check_existing_token; then
        token_ready=true
    fi
    
    # If no existing token or user wants new one, create it
    while [[ "$token_ready" == "false" ]] && [[ $token_attempts -lt $max_attempts ]]; do
        if create_github_token && test_github_token; then
            token_ready=true
        else
            ((token_attempts++))
            if [[ $token_attempts -lt $max_attempts ]]; then
                log_warning "Attempt $token_attempts failed, trying again..."
                echo ""
            else
                log_error "Failed to create valid token after $max_attempts attempts"
                exit $EXIT_TOKEN_INVALID
            fi
        fi
    done
    
    if [[ "$token_ready" == "false" ]]; then
        log_error "No valid token available"
        exit $EXIT_TOKEN_INVALID
    fi
    
    # Download management script
    download_management_script || exit $EXIT_DOWNLOAD_FAILED
    
    # Secure token and cleanup
    finalize_setup
    
    # LAST ACTION: Execute management script - NO MORE MESSAGES AFTER THIS
    log_info "Starting KuBu VPS deployment via management script..."
    echo ""
    
    # Execute management script - this will handle all deployment and welcome message
    exec sudo GITHUB_TOKEN="$(cat $SECURE_TOKEN_FILE)" /srv/scripts/manage-kubu-vps.sh deploy --force
}

# Check if running as root (not recommended)
if [[ $EUID -eq 0 ]]; then
    log_warning "Running as root is not recommended"
    echo "Consider running as a regular user with sudo access"
    if ! ask_continue "Continue anyway?"; then
        exit $EXIT_USER_CANCELLED
    fi
fi

# Run main function
main "$@"
