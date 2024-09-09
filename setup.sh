#!/bin/bash

# SystemGuard Installer Script
# ----------------------------
# This script installs, uninstalls, backs up, restores SystemGuard, and includes load testing using Locust.
# Determine the correct user's home directory

set -e
trap 'echo "An error occurred. Exiting..."; exit 1;' ERR

# run this script with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this program with sudo, exiting..."
    exit 1
fi

# Function to generate colored ASCII art from text using figlet
generate_ascii_art() {
  local text="$1"
  local color_code="$2"
  
  # Define color codes with default to reset if not specified
  local color_reset="\033[0m"
  local color="$color_reset"

  case "$color_code" in
    red)    color="\033[31m" ;;  # Red
    green)  color="\033[32m" ;;  # Green
    yellow) color="\033[33m" ;;  # Yellow
    blue)   color="\033[34m" ;;  # Blue
    magenta) color="\033[35m" ;; # Magenta
    cyan)   color="\033[36m" ;;  # Cyan
    white)  color="\033[37m" ;;  # White
    *)      color="$color_reset" ;; # Default to no color
  esac

  # Print the ASCII art with color
  echo -e "${color}$(figlet "$text")${color_reset}"
}

log() {
    # Check if the level is passed; if not, set it to "INFO" as default.
    local level="${1:-INFO}"
    local message

    # Check if a second argument exists, indicating that the first is the level.
    if [ -z "$2" ]; then
        message="$1"  # Only message is passed, assign the first argument to message.
        level="INFO"  # Default level when only message is passed.
    else
        message="$2"  # When both level and message are passed.
    fi

    # Define colors based on log levels.
    local color_reset="\033[0m"
    local color_debug="\033[1;34m"   # Blue
    local color_info="\033[1;32m"    # Green
    local color_warning="\033[1;33m" # Yellow
    local color_error="\033[1;31m"   # Red
    local color_critical="\033[1;41m" # Red background

    # Select color based on level.
    local color="$color_reset"
    case "$level" in
        DEBUG)
            color="$color_debug"
            ;;
        INFO)
            color="$color_info"
            ;;
        WARNING)
            color="$color_warning"
            ;;
        ERROR)
            color="$color_error"
            ;;
        CRITICAL)
            color="$color_critical"
            ;;
        *)
            color="$color_reset"  # Default to no color if the level is unrecognized.
            ;;
    esac

    # Log the message with timestamp, level, and message content, applying the selected color.
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${color}[$level]${color_reset} - $message" | tee -a "$LOG_FILE"
}

# introductary message
generate_ascii_art "SystemGuard" "yellow"
generate_ascii_art "Installer" "yellow"
generate_ascii_art "By" "yellow"
generate_ascii_art "CodePerfectPlus" "yellow"

# function to check for required dependencies
check_dependencies() {
    # List of required dependencies
    local dependencies=(git curl wget unzip iptables)
    
    # Check if `apt-get` is available
    if ! command -v apt-get &> /dev/null; then
        log "ERROR" "This script requires apt-get but it is not available."
        exit 1
    fi

    # Array to keep track of missing dependencies
    local missing_dependencies=()
    
    # Check each dependency
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_dependencies+=("$cmd")
        fi
    done

    # If there are missing dependencies, prompt the user for installation
    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log "The following dependencies are missing: ${missing_dependencies[*]}"
        echo "Do you want to install them now? (y/n)"
        read -r choice
        if [ "$choice" == "y" ]; then
            sudo apt-get install -y "${missing_dependencies[@]}"
        else
            log "Please install the required dependencies and run the script again."
            exit 1
        fi
    else
        log "All required dependencies are already installed."
    fi
}



# Function to set systemguard_auto_update variable permanently
set_auto_update() {
    local env_file="$USER_HOME/.bashrc" # Default file for setting environment variables

    # Prompt user for input
    echo "Do you want to enable systemguard_auto_update? (true/false)"
    echo "This will enable automatic updates for SystemGuard."
    read -p "Enter your choice: " auto_update

    # Validate input
    if [[ "$auto_update" != "true" && "$auto_update" != "false" ]]; then
        echo "Invalid input. Please enter 'true' or 'false'."
        return 1
    fi

    # Check if the variable is already set
    if grep -q '^export systemguard_auto_update=' "$env_file"; then
        # Update existing entry
        sed -i "s/^export systemguard_auto_update=.*/export systemguard_auto_update=$auto_update/" "$env_file"
    else
        # Add new entry
        echo "export systemguard_auto_update=$auto_update" >> "$env_file"
    fi

    # Notify user and reload the environment file
    echo "systemguard_auto_update set to $auto_update in $env_file."
    source "$env_file"
}

get_user_home() {
    if [ -n "$SUDO_USER" ]; then
        # When using sudo, SUDO_USER gives the original user who invoked sudo
        TARGET_USER="$SUDO_USER"
    else
        # If not using sudo, use LOGNAME to find the current user
        TARGET_USER="$LOGNAME"
    fi
    
    # Get the home directory of the target user
    USER_HOME=$(eval echo ~$TARGET_USER)
    echo "$USER_HOME"
}

# Retrieve the home directory of the current user
USER_HOME=$(get_user_home)
USER_NAME=$(basename "$USER_HOME")

# Define directories and file paths
DOWNLOAD_DIR="/tmp"
APP_NAME="SystemGuard"
EXTRACT_DIR="$USER_HOME/.systemguard"
GIT_INSTALL_DIR="$EXTRACT_DIR/${APP_NAME}-git"
LOG_DIR="$USER_HOME/logs"
LOG_FILE="$LOG_DIR/systemguard-installer.log"
BACKUP_DIR="$USER_HOME/.systemguard_backup"
EXECUTABLE_APP_NAME="systemguard-installer"
EXECUTABLE="/usr/local/bin/$EXECUTABLE_APP_NAME"

# File paths related to the application
HOST_URL="http://localhost:5050"
INSTALLER_SCRIPT='setup.sh'
FLASK_LOG_FILE="$USER_HOME/logs/systemguard_flask.log"

# Number of backups to keep
NUM_OF_BACKUP=5

# Pattern for identifying cron jobs related to SystemGuard
CRON_PATTERN=".systemguard/${APP_NAME}-.*/src/scripts/dashboard.sh"

# GitHub repository details
GIT_USER="codeperfectplus"
GIT_REPO="$APP_NAME"
GIT_URL="https://github.com/$GIT_USER/$GIT_REPO"
ISSUE_URL="$GIT_URL/issues"

# ENVIRONMENT VARIABLES
CONDA_ENV_NAME="systemguard"

# systemguard authentication
SYSTEMGUARD_USERNAME="admin"
SYSTEMGUARD_PASSWORD="admin"

# Function to create a directory if it does not exist
create_and_own_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || { log "ERROR" "Failed to create directory: $dir"; exit 1; }
        chown "$USER_NAME:$USER_NAME" "$dir" || { log "ERROR" "Failed to change ownership of directory: $dir"; exit 1; }
    fi
}

create_and_own_dir "$LOG_DIR"
create_and_own_dir "$BACKUP_DIR"


# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
    crontab_cmd="crontab -u $USER_NAME"
else
    crontab_cmd="crontab"
fi

# this function will change the ownership of the directory
# from root to the user, as the script is run as root
# and the installation directory should be owned by the user
change_ownership() {
    local directory="$1"
    if [ -d "$directory" ]; then
        # if permission is set to root then change it to the user
        if [ "$(stat -c %U "$directory")" == "root" ]; then
            chown -R "$USER_NAME:$USER_NAME" "$directory"
            log "INFO" "Ownership changed from root to $USER_NAME for $directory"
        fi
    fi
}

# check if conda is installed or not
check_conda() {
    CONDA_PATHS=("/home/$USER_NAME/miniconda3" "/home/$USER_NAME/anaconda3")
    CONDA_FOUND=false

    # Find Conda installation
    for CONDA_PATH in "${CONDA_PATHS[@]}"; do
        if [ -d "$CONDA_PATH" ]; then
            CONDA_EXECUTABLE="$CONDA_PATH/bin/conda"
            CONDA_SETUP_SCRIPT="$CONDA_PATH/etc/profile.d/conda.sh"
            CONDA_FOUND=true
            break
        fi
    done

    if [ "$CONDA_FOUND" = false ]; then
        log "ERROR" "Conda not found. Please install Conda or check your Conda paths."
        exit 1
    fi
    echo "Conda executable: $CONDA_EXECUTABLE"
}

# Function to add a cron job with error handling
add_cron_job() {

    # Define log directory and cron job command
    local log_dir="$USER_HOME/logs"
    local script_path=$(find "$EXTRACT_DIR" -name dashboard.sh)
    local cron_job="* * * * * /bin/bash $script_path >> $log_dir/systemguard_cron.log 2>&1"

    # Create log directory with error handling
    if [ $? -ne 0 ]; then
        log "CRITICAL" "Failed to create log directory: $log_dir"
        exit 1
    fi


    # Temporarily store current crontab to avoid overwriting on error
    local temp_cron=$(mktemp)
    if [ $? -ne 0 ]; then
        log "CRITICAL "Failed to create temporary file for crontab."
        exit 1
    fi

    # List the current crontab
    if ! $crontab_cmd -l 2>/dev/null > "$temp_cron"; then
        log "CRITICAL" "Unable to list current crontab."
        rm "$temp_cron"
        exit 1
    fi

    # Ensure the cron job does not already exist
    if grep -Fxq "$cron_job" "$temp_cron"; then
        log "Cron "job already exists: $cron_job"
        rm "$temp_cron"
        exit 0
    fi

    # Add the new cron job
    echo "$cron_job" >> "$temp_cron"
    if ! $crontab_cmd "$temp_cron"; then
        log "ERROR" "Failed to add the cron job to crontab."
        rm "$temp_cron"
        exit 1
    fi

    rm "$temp_cron"
    log "INFO" "Cron job added successfully" 
    # log $cron_job
}

# Function to clean up all backups
cleanup_backups() {
    log "INFO" "Cleaning up all backups in $BACKUP_DIR..."
    
    # Check if the backup directory exists
    if [ -d "$BACKUP_DIR" ]; then
        # List all items in the backup directory
        local backups=( $(ls -A "$BACKUP_DIR") )
        
        # Check if there are any backups to remove
        if [ ${#backups[@]} -gt 0 ]; then
            # Loop through each item and remove it
            for backup in "${backups[@]}"; do
                rm -rf "$BACKUP_DIR/$backup"
                log "INFO" "Removed backup: $backup"
            done
            log "INFO" "All backups have been cleaned up."
        else
            log "INFO" "No backups found to clean up."
        fi
    else
        log "ERROR" "Backup directory $BACKUP_DIR does not exist."
    fi
}

# Function to rotate backups and keep only the latest n backups
rotate_backups() {
    local num_of_backup=$1
    log "INFO" "Rotating backups... Keeping last $num_of_backup backups."
    local backups=( $(ls -t $BACKUP_DIR) )
    local count=${#backups[@]}
    if [ "$count" -gt "$num_of_backup" ]; then
        local to_remove=( "${backups[@]:$num_of_backup}" )
        for backup in "${to_remove[@]}"; do
            rm -rf "$BACKUP_DIR/$backup"
            log "INFO" "Removed old backup: $backup"
        done
    fi
}
# Backup function for existing configurations
backup_configs() {
    rotate_backups $NUM_OF_BACKUP
    log "Backing up existing configurations..."
    if [ -d "$EXTRACT_DIR" ]; then
        cp -r "$EXTRACT_DIR" "$BACKUP_DIR/$(date '+%Y%m%d_%H%M%S')"
        log "Backup completed: $BACKUP_DIR"
    else
        log "No existing installation found to back up."
    fi
}

# Restore function to restore from a backup
restore() {
    log "Starting restore process..."
    
    # List available backups
    if [ -d "$BACKUP_DIR" ]; then
        echo "Available backups:"
        select BACKUP in "$BACKUP_DIR"/*; do
            if [ -n "$BACKUP" ]; then
                echo "You selected: $BACKUP"
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
        
        # Confirm restoration
        echo "Are you sure you want to restore this backup? This will overwrite the current installation. (y/n)"
        read CONFIRM
        if [ "$CONFIRM" != "y" ]; then
            log "WARNING" "Restore aborted by user."
            exit 0
        fi
        
        # Remove existing installation
        if [ -d "$EXTRACT_DIR" ]; then
            rm -rf "$EXTRACT_DIR"
            log "Old installation removed."
        fi
        
        # Restore selected backup
        cp -r "$BACKUP" "$EXTRACT_DIR"
        log "Restore completed from backup: $BACKUP"
    else
        log "WARNING" "No backups found to restore."
    fi
}

# Function to install the script as an executable
install_executable() {
    # Use $0 to get the full path of the currently running script
    # CURRENT_SCRIPT=$(realpath "$0")
    cd $EXTRACT_DIR/$APP_NAME-*/
    CURRENT_SCRIPT=$(pwd)/$INSTALLER_SCRIPT  
    # Verify that the script exists before attempting to copy
    if [ -f "$CURRENT_SCRIPT" ]; then
        log "Installing executable to /usr/local/bin/systemguard-installer..."
        cp "$CURRENT_SCRIPT" "$EXECUTABLE"
        log "Executable installed successfully."
    else
        log "ERROR" "Script file not found. Cannot copy to /usr/local/bin."
    fi
}

# remove extract directory, break below functions
# if the directory is not present
remove_extract_dir() {
    if [ -d "$EXTRACT_DIR" ]; then
        rm -rf "$EXTRACT_DIR"
        log "Old installation removed."
    else
        log "No previous installation found."
    fi
}

remove_cronjob () {
    if $crontab_cmd -l | grep -q "$CRON_PATTERN"; then
        $crontab_cmd -l | grep -v "$CRON_PATTERN" | $crontab_cmd -
        log "Old cron jobs removed."
    else
        log "No previous cron jobs found."
    fi
}
# remove previous installation of cron jobs and SystemGuard
remove_previous_installation() {
    remove_extract_dir
    remove_cronjob 
}

# Function to fetch the latest version of SystemGuard from GitHub releases
fetch_latest_version() {
    log "Fetching the latest version of $APP_NAME from GitHub..."
    VERSION=$(curl -s https://api.github.com/repos/$GIT_USER/$GIT_REPO/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    if [ -z "$VERSION" ]; then
        log "ERROR" "Unable to fetch the latest version. Please try again or specify a version manually."
        exit 1
    fi
    log "Latest version found: $VERSION"
}

# Function to download a release from a given URL
download_release() {
    local url=$1
    local output=$2
    log "Downloading $APP_NAME from $url..."
    if ! wget -q "$url" -O "$output"; then
        log "ERROR" "Failed to download $APP_NAME. Please check the URL and try again."
        exit 1
    fi
    log "Download completed successfully."
}

# Function to setup the cron job for SystemGuard
setup_cron_job() {
    log "Preparing cron job script..."
    add_cron_job
    if $crontab_cmd -l | grep -q "$CRON_PATTERN"; then
        log "Cron job added successfully."
    else
        log "ERROR" "Failed to add the cron job."
        exit 1
    fi
}

# Function to install SystemGuard from Git repository
install_from_git() {
    log "Starting installation of $APP_NAME from Git repository..."

    # Backup existing configurations
    backup_configs

    # Remove any previous installations
    remove_previous_installation

    
    echo ""
    echo "Select the version of $APP_NAME to install:"
    echo "|-----------------------------------------------------------------------------|"
    echo "|  1. Production (stable)  -       Recommended for most users                 |"
    echo "|  2. Development (dev)    -       Latest features, may be unstable           |"
    echo "|  3. Specify a branch     -       Enter the branch/tag name when prompted    |"
    echo "|-----------------------------------------------------------------------------|"
    echo "Enter the number of your choice:"
    read -r VERSION

    # Set Git URL based on user choice
    case "$VERSION" in
        1|"")  # Stable is the default option if nothing is entered
            BRANCH="production"
            log "Selected Production (stable branch)."
            ;;
        2)  # Development version
            BRANCH="dev"
            log "Selected Development (dev branch)."
            ;;
        3)  # Specific branch
            echo "Enter the branch name to install:"
            read -r BRANCH
            log "Selected branch: $BRANCH."
            ;;
        *)  # Invalid input handling
            log "WARNING" "Invalid selection. Please enter '1' for Stable, '2' for Development, or '3' to specify a branch."
            exit 1
            ;;
    esac

    # Construct the full Git URL with branch
    FULL_GIT_URL="https://github.com/codeperfectplus/SystemGuard.git -b $BRANCH"

    set_auto_update
    
    log "Cloning the $APP_NAME repository from GitHub..."
    create_and_own_dir "$GIT_INSTALL_DIR"
    check_conda # check if conda is installed
    
    if ! git clone $FULL_GIT_URL "$GIT_INSTALL_DIR"; then
        log "ERROR" "Failed to clone the repository. Please check your internet connection and the branch name, and try again."
        exit 1
    fi

    log "Repository cloned successfully."

    install_conda_env # if conda is installed then install the conda environment

    # Change to the installation directory
    cd "$GIT_INSTALL_DIR" || { 
        log "ERROR" "Failed to navigate to the installation directory."; 
        exit 1; 
    }

    log "Setting up $APP_NAME from Git repository..."

    # Install the executable
    install_executable

    log "$APP_NAME installed successfully from Git!"

    # Set up the cron job if necessary
    setup_cron_job

    # Change ownership of the installation directory
    change_ownership "$EXTRACT_DIR"

    log "Installation complete. $APP_NAME is ready to use."
}

# install the latest version of SystemGuard from the release
install_from_release() {
    echo "Enter the version of $APP_NAME to install (e.g., v1.0.0 or 'latest' for the latest version):"
    read -r VERSION

    [ "$VERSION" == "latest" ] && fetch_latest_version

    ZIP_URL="$GIT_URL/archive/refs/tags/$VERSION.zip"
    log "Installing $APP_NAME version $VERSION..."

    download_release "$ZIP_URL" "$DOWNLOAD_DIR/systemguard.zip"

    backup_configs
    remove_previous_installation

    log "Setting up installation directory..."

    log "Extracting $APP_NAME package..."
    unzip -q "$DOWNLOAD_DIR/systemguard.zip" -d "$EXTRACT_DIR"
    rm "$DOWNLOAD_DIR/systemguard.zip"
    log "Extraction completed."

    check_conda # check if conda is installed
    install_conda_env # if conda is installed then install the conda environment

    install_executable
    setup_cron_job

    change_ownership "$EXTRACT_DIR"
    log "$APP_NAME version $VERSION installed successfully!"
    log "Server may take a few minutes to start. If you face any issues, try restarting the server."
}

display_credentials() {
    log "INFO" "You can now login to the server using the following credentials:"
    log "INFO" "Username: $SYSTEMGUARD_USERNAME"
    log "INFO" "Password: $SYSTEMGUARD_PASSWORD"
}

# Install function
install() {
    check_dependencies
    log "Starting installation of $APP_NAME..."
    create_and_own_dir "$EXTRACT_DIR"
    echo ""
    echo "Do you want to install from a Git repository or a specific release?"
    echo "|----------------------------------------------------|"
    echo "|           1. Git repository                        |"
    echo "|           2. Release                               |"
    echo "|----------------------------------------------------|"
    echo "Enter the number of your choice:"
    read -r INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            install_from_git
            ;;
        2)
            install_from_release
            ;;
        *)
            log "Invalid installation method. Please choose '1' for Git repository or '2' for Release."
            exit 1
            ;;
    esac
	stop_server
	generate_ascii_art "SystemGuard Installed" "green"
    display_credentials

}
# Uninstall function
uninstall() {
    log "Uninstalling $APP_NAME..."
    remove_previous_installation
	stop_server
	generate_ascii_art "SystemGuard Uninstalled" "red"
}

# Load test function to start Locust server
load_test() {
    log "Starting Locust server for load testing..."
    echo "It's for advanced users only. Do you want to continue? (y/n)"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        log "Load test aborted by user."
        exit 0
    fi
    
    # Check if Locust is installed
    if ! command -v locust &> /dev/null
    then
        log "WARNING" "Locust is not installed. Please install it first."
        exit 1
    fi

    # Start Locust server
    log "Starting Locust server..."
    LOCUST_FILE=$(find "$EXTRACT_DIR" -name "locustfile.py" | head -n 1)
    echo "locust file: $LOCUST_FILE"
    locust -f "$LOCUST_FILE" --host="$HOST_URL"
}

# Check if SystemGuard is installed
check_status() {
    log "Checking $APP_NAME status..."
    
    if [ -d "$EXTRACT_DIR" ]; then
        log "$APP_NAME is installed at $EXTRACT_DIR."
    else
        log "$APP_NAME is not installed."
    fi

    
    if $crontab_cmd '-l' | grep -q "$CRON_PATTERN"; then
        log "Cron job for $APP_NAME is set."
    else
        log "No cron job found for $APP_NAME."
    fi

    health_check
}

# Health check by pinging localhost:5050 every 30 seconds
health_check() {
    local sleep_time=30
    local max_retries=5
    local retries=0
    
    # Check if HOST_URL is set
    if [[ -z "$HOST_URL" ]]; then
        log "ERROR" "HOST_URL is not set. Exiting."
        exit 1
    fi

    while (( retries < max_retries )); do
        log "Performing health check on $HOST_URL..."
        
        # Get the HTTP response code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" "$HOST_URL")
        
        # Check if the response code indicates success
        if [[ $response_code -eq 200 || $response_code -eq 302 ]]; then
            log "Health check successful: $HOST_URL is up and running."
            generate_ascii_art "SystemGuard is UP" "green"
            exit 0
        else
            ((retries++))
            log "WARNING" "Health check failed: $HOST_URL is not responding (HTTP $response_code)."
            log "WARNING" "Retry $retries of $max_retries. Next health check in $sleep_time seconds."
            sleep "$sleep_time"
        fi
    done
    
    # If max retries are reached, log the failure and exit with an error
    log "ERROR" "Max retries reached. $HOST_URL is still not responding. Exiting with error."
    generate_ascii_art "SystemGuard is DOWN" "red"
    exit 1
}


# app logs
show_server_logs() {
    log "INFO" "Press Ctrl+C to exit."
    echo ""
    echo "--- Server Logs ---"
    echo ""
    
    cd $EXTRACT_DIR/$APP_NAME-*/
    log_file=$(find . -name "app_debug.log" | head -n 1)
    echo "log file: $log_file"
    if [ -f "$log_file" ]; then
        log "Server log file: $log_file"
        tail -100f "$log_file"
    else
        log "No logs found at $log_file."
    fi
}

# installation logs
show_installer_logs() {
    log "INFO" "Press Ctrl+C to exit."
    echo ""
    echo "--- Installer Logs ---"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        log "Installer log file: $LOG_FILE"
        tail -100f "$LOG_FILE"
    else
        log "No logs found at $LOG_FILE."
    fi
}

update_dependencies() {
    # Activate Conda environment
    check_conda
    source "$CONDA_SETUP_SCRIPT"
    conda activate "$CONDA_ENV_NAME" || { log "ERROR" "Failed to activate Conda environment $CONDA_ENV_NAME"; exit 1; }
    
    # Check for missing dependencies
    log "INFO" "Checking for missing dependencies..."
    cd $EXTRACT_DIR/$APP_NAME-*/ || { log "ERROR" "Failed to change directory to $EXTRACT_DIR/$APP_NAME-*/"; exit 1; }
    REQUIREMENTS_FILE="requirements.txt"

    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        log "ERROR" "Requirements file $REQUIREMENTS_FILE not found."
        exit 1
    fi

    log "INFO" "Installing dependencies from $REQUIREMENTS_FILE..."

    # Install dependencies silently
    sudo -u "$SUDO_USER" bash -c "source $CONDA_SETUP_SCRIPT && conda activate $CONDA_ENV_NAME && pip install -r $EXTRACT_DIR/$APP_NAME-*/$REQUIREMENTS_FILE" > /dev/null 2>&1 || {
        log "ERROR" "Failed to install dependencies from $REQUIREMENTS_FILE."
        exit 1
    }

    log "INFO" "Dependencies installation complete."
}

# Function to install Conda environment and dependencies
install_conda_env() {
    log "Checking conda environment $CONDA_ENV_NAME..."
    if ! "$CONDA_EXECUTABLE" env list | grep -q "$CONDA_ENV_NAME"; then
        log "Creating Conda environment $CONDA_ENV_NAME..."
        "$CONDA_EXECUTABLE" create -n "$CONDA_ENV_NAME" python=3.8 -y || { log "ERROR" "Failed to create Conda environment $CONDA_ENV_NAME"; exit 1; }
        # install the dependencies
        update_dependencies
    else
        log "Conda environment $CONDA_ENV_NAME already exists."
        update_dependencies
    fi
}


# stop flask server
stop_server_helper() {    
    if lsof -Pi :5050 -sTCP:LISTEN -t >/dev/null; then
        kill -9 $(lsof -t -i:5050)
        log "Server stopped successfully."
    else
        log "Server is not running."
    fi
}

stop_server() {
    log "Stopping $APP_NAME server..."
    stop_server_helper
}

# fix the server
fix() {
    update_dependencies
    log "Fixing $APP_NAME server..."
    stop_server
}

# update the code to the latest version
install_latest() {
    cd $EXTRACT_DIR/$APP_NAME-*/
    # check if the .git directory exists
    if [ -d ".git" ]; then
        log "Fetching the server for the latest version..."
        # sleep 3 seconds
        # some kind of animation of fetching the latest code
        echo -n "connecting to the SystemGuard server"
        for i in {1..3}; do
            echo -n "..."
            sleep 1
        done
        echo ""
        echo -n "connected now fetching the latest code"
        for i in {1..3}; do
            echo -n "..."
            sleep 1
        done
        echo ""
        git pull >> /dev/null 2>&1 || { log "ERROR" "Failed to update the code. Please check your internet connection and try again."; exit 1; }
        log "Hurray: Code updated successfully."
    else
        log "Probably you have installed the code from the release, so you can't update the code."
        log "Please install the code from the git repository to update the code."
    fi
}

# Display help
show_help() {
    echo "$APP_NAME Installer"
    echo ""
    echo "Usage: $EXECUTABLE_APP_NAME [options]"
    echo ""
    echo "Options:"
    echo "  --install           Install $APP_NAME and set up all necessary dependencies."
    echo "                      This will configure the environment and start the application."
    echo ""
    echo "  --uninstall         Uninstall $APP_NAME completely."
    echo "                      This will remove the application and all associated files."
    echo ""
    echo "  --fix               Fix the $APP_NAME installation errors."
    echo "                      This will fix any issues with the installation and restart the server."
    echo ""   
    echo "  --restore           Restore $APP_NAME from a backup."
    echo "                      Use this option to recover data or settings from a previous backup."
    echo ""
    echo "  --load-test         Start Locust load testing for $APP_NAME."
    echo "                      This will initiate performance testing to simulate multiple users."
    echo ""
    echo "  --status            Check the status of $APP_NAME installation."
    echo "                      Displays whether $APP_NAME is installed, running, or if there are any issues."
    echo ""
    echo "  --health-check      Perform a health check on $HOST_URL."
    echo "                      Verifies that the application is running correctly and responding to requests."
    echo ""
    echo "  --clean-backups     Clean up all backups of $APP_NAME."
    echo "                      This will delete all saved backup files to free up space."
    echo ""
    echo "  --logs              Show server logs for $APP_NAME."
    echo "                      Displays the latest server logs, which can help in troubleshooting issues."
    echo "                      Press Ctrl+C to exit the log viewing session."
    echo ""
    echo " --installation-logs  Show installer logs for $APP_NAME."
    echo "                      Displays the logs generated during the installation process."
    echo "                      Press Ctrl+C to exit the log viewing session."
    echo ""
    echo "  --server-stop       Stop the $APP_NAME server."
    echo "                      This will stop the running server instance."
    echo ""
    echo " --install-latest     Update the code to the latest version."
    echo "                      This will pull the latest code from the Git repository."
    echo ""
    echo ""
    echo " --check-conda        Check if Conda is installed and available."
    echo "                      This will verify the presence of Conda and display the installation path."
    echo ""
    echo " --update-dependencies Update the dependencies for $APP_NAME."
    echo "                      This will install any missing dependencies required for the application."
    echo ""
    echo "  --help              Display this help message."
    echo "                      Shows information about all available options and how to use them."
}


# Parse command-line options
for arg in "$@"; do
    case $arg in
        --install) ACTION="install" ;;
        --uninstall) ACTION="uninstall" ;;
        --restore) ACTION="restore" ;;
        --load-test) ACTION="load_test" ;;
        --status) ACTION="check_status" ;;
        --health-check) ACTION="health_check" ;;
        --clean-backups) ACTION="cleanup_backups" ;;
        --logs) show_server_logs; exit 0 ;;
        --installation-logs) show_installer_logs; exit 0 ;;
        --server-stop) stop_server; exit 0 ;;
        --fix) fix; exit 0 ;;
        --update-dependencies) update_dependencies; exit 0 ;;
        --check-conda) check_conda; exit 0 ;;
        --install-latest) ACTION="install_latest" ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $arg"; show_help; exit 1 ;;
    esac
done

# Execute based on the action specified
case $ACTION in
    install) install ;;
    uninstall) uninstall ;;
    restore) restore ;;
    load_test) load_test ;;
    check_status) check_status ;;
    health_check) health_check ;;
    cleanup_backups) cleanup_backups ;;
    stop_server) stop_server ;;
    logs) show_server_logs ;;
    installation-logs) show_installer_logs ;;
    fix) fix ;;
    check-conda) check_conda ;;
    install_latest) install_latest ;;
    update_dependencies) update_dependencies ;;
    *) echo "No action specified. Use --help for usage information." ;;
esac
