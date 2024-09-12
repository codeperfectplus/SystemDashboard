#!/bin/bash

# App Installer Script
# ----------------------------
# This script installs, uninstalls, backs up, restores App, and includes load testing using Locust.

# USER_NAME=$(logname 2>/dev/null || echo $SUDO_USER)
USER_NAME=$USER
if [ "$(whoami)" = "root" ]; then
    # LOGNAME_USER=$(logname)
    # echo $LOGNAME_USER
    # if [ "$LOGNAME_USER" = "logname: no login name" ]; then
    LOGNAME_USER=$(logname 2>/dev/null)  # Redirect any error output to /dev/null
    if [ $? -ne 0 ]; then  # Check if the exit status of the last command is not 0
        echo "No login name found. Using fallback method."
        # use head -n 1 for native linux. tail -n 1 works with wsl.
        USER_NAME=$(cat /etc/passwd | grep '/home' | cut -d: -f1 | tail -n 1)
    else
        USER_NAME=$LOGNAME_USER
    fi
else
    USER_NAME=$(whoami)
fi
USER_HOME=/home/$USER_NAME


# Define directories and file paths
DOWNLOAD_DIR="/tmp"
APP_NAME="SystemGuard"
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
EXTRACT_DIR="$USER_HOME/.$APP_NAME_LOWER"
GIT_INSTALL_DIR="$EXTRACT_DIR/${APP_NAME}-git"
SOURCE_INSTALL_DIR="$EXTRACT_DIR/${APP_NAME}-source"
LOG_DIR="$USER_HOME/logs"
LOG_FILE="$LOG_DIR/$APP_NAME_LOWER-installer.log"
BACKUP_DIR="$USER_HOME/.$APP_NAME_LOWER-backup"
EXECUTABLE="/usr/local/bin/$APP_NAME_LOWER-installer"

# Application-related file paths
HOST_URL="http://localhost:5050"
INSTALLER_SCRIPT="setup.sh"
FLASK_LOG_FILE="$LOG_DIR/flask.log"

# Cron job pattern
CRON_PATTERN=".$APP_NAME_LOWER/${APP_NAME}-.*/src/scripts/dashboard.sh"

# GitHub repository details
GITHUB_USER="codeperfectplus"
GITHUB_REPO="$APP_NAME"
GITHUB_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO"
ISSUE_TRACKER_URL="$GITHUB_URL/issues"
NUM_OF_RELEASES=5
NUM_OF_RETRIES=5

# Backup settings
NUM_BACKUPS=5

# Environment variables
ENV_FILE="$USER_HOME/.bashrc"  # Default environment file

# authentication
ADMIN_LOGIN="admin"
ADMIN_PASSWORD="admin"

set -e
trap 'echo "An error occurred. Exiting..."; exit 1;' ERR

# run this script with sudo
# if [ "$EUID" -ne 0 ]; then
#     echo "Please run this program with sudo, exiting..."
#     exit 1
# fi

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
generate_ascii_art "$APP_NAME" "yellow"
generate_ascii_art "Installer" "yellow"
generate_ascii_art "By" "yellow"
generate_ascii_art "CodePerfectPlus" "yellow"
echo "Welcome on board: $(echo "$USER_NAME" | sed 's/.*/\u&/')"


# function to check for required dependencies
check_dependencies() {
    # List of required dependencies
    local dependencies=(git curl wget unzip iptables figlet)

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

# Function to change ownership of a directory and its subdirectories
own_dir() {
    local dir="$1"
    chown -R "$USER_NAME:$USER_NAME" "$dir" || { log "ERROR" "Failed to change ownership of directory and its contents: $dir"; exit 11; }
}

# Function to create a directory if it does not exist
create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || { log "ERROR" "Failed to create directory: $dir"; exit 10; }
        own_dir "$dir" # Call own_dir to change ownership after creation
    fi
}

create_dir "$LOG_DIR"
create_dir "$BACKUP_DIR"

# Function to handle errors
handle_error() {
    local exit_code="$1"
    local message="$2"
    log "ERROR" "$message"
    exit "$exit_code"
}

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
    crontab_cmd="crontab -u $USER_NAME"
else
    crontab_cmd="crontab"
fi

# Function to create a environment variable in the .bashrc file
prompt_user() {
    echo "Do you want to enable $var_name for automatic updates for $APP_NAME?"
    echo "1) Yes (Enable automatic updates)"
    echo "2) No (Disable automatic updates)"
    read -p "Enter your choice (1 or 2): " user_choice
    
    # Convert the user's choice to true/false
    case "$user_choice" in
        1)
            user_choice="true"
            ;;
        2)
            user_choice="false"
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            return 1
            ;;
    esac
}

# Function to update the environment variable in the env file
update_env_variable() {
    var_name=$1
    var_value=$2
    
    # Ensure the environment file exists
    touch "$ENV_FILE"
    
    # Update or add the variable in the environment file
    if grep -q "^$var_name=" "$ENV_FILE"; then
        # Replace existing variable
        sed -i "s/^$var_name=.*/$var_name=$var_value/" "$ENV_FILE"
    else
        # Add new variable
        echo "$var_name=$var_value" >> "$ENV_FILE"
    fi
}

# Function to set the auto update variable
set_auto_update() {
    var_name=$1
    prompt_user # Prompt user for input
    
    # If prompt_user returned an error (invalid choice), exit early
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Update the environment variable with the user's choice
    update_env_variable "$var_name" "$user_choice"
    
    # Reload the environment file to apply changes
    source "$ENV_FILE"
}

# this function will change the ownership of the directory
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


# Function to add a cron job with error handling
add_cron_job() {

    # Define log directory and cron job command
    local log_dir="$USER_HOME/logs"
    local script_path=$(find "$EXTRACT_DIR" -name dashboard.sh)
    local cron_job="* * * * * /bin/bash $script_path >> $log_dir/$APP_NAME_LOWER-cron.log 2>&1"

    # Create log directory with error handling
    if [ $? -ne 0 ]; then
        log "CRITICAL" "Failed to create log directory: $log_dir"
        exit 1
    fi


    # Temporarily store current crontab to avoid overwriting on error
    local temp_cron=$(mktemp)
    if [ $? -ne 0 ]; then
        log "CRITICAL" "Failed to create temporary file for crontab."
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
        log "Cron job already exists: $cron_job"
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
    cd $EXTRACT_DIR/$APP_NAME-*/
    CURRENT_SCRIPT=$(pwd)/$INSTALLER_SCRIPT
    # Verify that the script exists before attempting to copy
    if [ -f "$CURRENT_SCRIPT" ]; then
        log "Installing executable to /usr/local/bin/$APP_NAME_LOWER-installer..."
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
# remove previous installation of cron jobs
remove_previous_installation() {
    remove_extract_dir
    remove_cronjob
}

# Function to fetch the latest version from GitHub releases
fetch_latest_version() {
    log "Fetching the latest version of $APP_NAME from GitHub..."

    # Fetch the latest version from GitHub
    API_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest"
    RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/latest_version.json "$API_URL")
    HTTP_CODE="${RESPONSE: -3}"  # Extract HTTP status code

    # Check for HTTP errors
    if [ "$HTTP_CODE" -ne 200 ]; then
        if [ "$HTTP_CODE" -eq 403 ]; then
            log "ERROR" "GitHub API rate limit exceeded. Try again later or provide a GitHub token."
        else
            log "ERROR" "Failed to fetch the latest version. HTTP status code: $HTTP_CODE."
        fi
        exit 1
    fi

    # Parse the version from the JSON response
    VERSION=$(grep -Po '"tag_name": "\K.*?(?=")' /tmp/latest_version.json)

    # Check if a version was found
    if [ -z "$VERSION" ]; then
        log "ERROR" "Unable to extract the version from the GitHub API response."
        exit 1
    fi

    log "Latest version found: $VERSION"
    echo "$VERSION"
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

# Function to setup the cron job
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

# Function to install from Git repository
install_from_git() {
    log "Starting installation of $APP_NAME from Git repository..."

    # Backup existing configurations
    backup_configs

    # Remove any previous installations
    remove_previous_installation

    echo ""
    echo "Select the version of $APP_NAME to install:"
    echo "|------------------------------------------------------------------------------|"
    echo "|  1. Production (stable)  ->       Recommended for most users                 |"
    echo "|  2. Development (dev)    ->       Latest features, may be unstable           |"
    echo "|  3. Specify a branch     ->       Enter the branch/tag name when prompted    |"
    echo "|------------------------------------------------------------------------------|"
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
            BRANCH="production"
            log "WARNING" "Invalid branch selected. Defaulting to 'production'."
            ;;
    esac

    # Construct the full Git URL with branch
    FULL_GIT_URL="$GITHUB_URL -b $BRANCH"

    set_auto_update "sg_auto_update"

    log "Cloning the $APP_NAME repository from GitHub..."
    create_dir "$GIT_INSTALL_DIR"
    if ! git clone $FULL_GIT_URL "$GIT_INSTALL_DIR"; then
        log "ERROR" "Failed to clone the repository. Please check your internet connection and the branch name, and try again."
        exit 30
    fi

    log "Repository cloned successfully."

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

# Function to fetch and display GitHub releases
fetch_github_releases() {
    local url="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to use this function."
        return 1
    fi

    # Fetch releases
    response=$(curl -s "$url")

    # Check if curl command was successful
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch releases from GitHub."
        return 1
    fi

    # Check if response contains a valid JSON
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        echo "Error: Failed to parse JSON response from GitHub."
        return 1
    fi

    # Display releases with newest first
    # Display releases with newest first in tabular format
    echo "--------------------------------------------"
    echo "Latest releases for $APP_NAME:"
    echo "--------------------------------------------"
    echo "$response" | jq -r '.[] | [.tag_name, .published_at] | @tsv' | sort -r -t $'\t' -k2,2 | awk -F'\t' 'BEGIN { printf "%-15s %-20s\n", "Tag Name", "Published At" } { printf "%-15s %-20s\n", $1, $2 }' | head -n $NUM_OF_RELEASES
    echo "--------------------------------------------"
    # Exit with status code 0
    return 0
}

# install the latest version of APP from the release
install_from_release() {
    fetch_github_releases
    echo "Enter the tag name of the release to install (e.g., v1.0.3) or 'latest' for the latest release:"
    read -r VERSION

    [ "$VERSION" == "latest" ] && fetch_latest_version

    ZIP_URL="$GITHUB_URL/archive/refs/tags/$VERSION.zip"
    log "Installing $APP_NAME version $VERSION..."

    download_release "$ZIP_URL" "$DOWNLOAD_DIR/$APP_NAME_LOWER.zip"

    backup_configs
    remove_previous_installation

    log "Setting up installation directory..."

    log "Extracting $APP_NAME package..."
    unzip -q "$DOWNLOAD_DIR/$APP_NAME_LOWER.zip" -d "$EXTRACT_DIR"
    rm "$DOWNLOAD_DIR/$APP_NAME_LOWER.zip"
    log "Extraction completed."

    install_executable
    setup_cron_job

    change_ownership "$EXTRACT_DIR"
    log "$APP_NAME version $VERSION installed successfully!"
}

install_using_setup_file_in_cwd() {
    # copy the code base from the current directory to the $SOURCE_INSTALL_DIR
    # make directory if not exists
    create_dir "$SOURCE_INSTALL_DIR"
    cp -r ./* "$SOURCE_INSTALL_DIR" || { log "ERROR" "Failed to copy the code to the installation directory."; exit 1; }
    own_dir "$SOURCE_INSTALL_DIR"
}

install_from_source_code() {
    backup_configs
    remove_previous_installation
    log "Using the current folder as the installation directory..."
    install_using_setup_file_in_cwd
    setup_cron_job
    log "$APP_NAME version $VERSION installed successfully!"
}

display_credentials() {
    log "INFO" "You can now login to the server using the following credentials:"
    log "INFO" "Username: $ADMIN_LOGIN"
    log "INFO" "Password: $ADMIN_PASSWORD"
}

timer() {
    local duration=$1
    for ((i=1; i<=duration; i++)); do
        echo -n "$i "
        sleep 1
        echo -ne "\r" # Delete previous number to show next
    done
    echo -ne "\n" # Move to the next line after the timer completes
}

open_browser() {
    log "If you face server server issues, run 'sudo $APP_NAME_LOWER-installer --fix' to fix the installation."
    log "Server is opening in the default browser..., waiting for 5 seconds."
    timer 5

    if [ "$(id -u)" = "0" ]; then
        sudo -u "$SUDO_USER" xdg-open "$HOST_URL" &  # Linux with xdg-open
    else
        # If running as a normal user, use xdg-open or open (for macOS)
        if command -v xdg-open &> /dev/null; then
            xdg-open "$HOST_URL" &
        elif command -v open &> /dev/null; then
            open "$HOST_URL" &
        else
            log "ERROR" "Unable to open the browser. Please open the browser and navigate to $HOST_URL."
        fi
    fi
}

# Install function
install() {
    check_dependencies
    log "Starting installation of $APP_NAME..."
    create_dir "$EXTRACT_DIR"
    echo ""
    echo "Would you like to install from a Git repository or a specific release?"
    echo "For production use, it is recommended to install from a release."
    echo "|------------------------------------------------------------|"
    echo "|       1. Git Repository (Pre-Release Version)              |"
    echo "|       2. Release (More Stable Version)                     |"
    echo "|       3. Source Code (Current Directory)                   |"
    echo "|------------------------------------------------------------|"
    echo "Enter the number of your choice:"
    read -r INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            install_from_git
            ;;
        2)
            install_from_release
            ;;
        3)
            install_from_source_code
            ;;
        *)
            log "Invalid installation method. Please choose '1' for Git repository or '2' for Release."
            exit 1
            ;;
    esac
	generate_ascii_art "$APP_NAME Installed" "green"
    display_credentials
    cd $EXTRACT_DIR/$APP_NAME-*/
    dashboard_script_path=$(find . -name dashboard.sh | head -n 1)
    sudo -u "$USER_NAME" bash "$dashboard_script_path" &> /dev/null
    open_browser
}
# Uninstall function
uninstall() {
    log "Uninstalling $APP_NAME..."
    remove_previous_installation
	stop_server
	generate_ascii_art "$APP_NAME Uninstalled" "red"
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

# Check if APP is installed
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
            generate_ascii_art "$APP_NAME is UP" "green"
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
    generate_ascii_art "$APP_NAME is DOWN" "red"
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
    log "Fixing $APP_NAME server..."
    stop_server
    open_browser
}

# update the code to the latest version
install_latest() {
    cd $EXTRACT_DIR/$APP_NAME-*/
    # check if the .git directory exists
    if [ -d ".git" ]; then
        log "Fetching the server for the latest version..."
        # sleep 3 seconds
        # some kind of animation of fetching the latest code
        echo -n "connecting to the $APP_NAME server"
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
    echo "  --install                  Install $APP_NAME and set up all necessary dependencies."
    echo "                             This will configure the environment and start the application."
    echo ""
    echo "  --uninstall                Uninstall $APP_NAME completely."
    echo "                             This will remove the application and all associated files."
    echo ""
    echo "  --fix                      Fix the $APP_NAME installation errors."
    echo "                             This will fix any issues with the installation and restart the server."
    echo ""
    echo "  --restore                  Restore $APP_NAME from a backup."
    echo "                             Use this option to recover data or settings from a previous backup."
    echo ""
    echo "  --load-test                Start Locust load testing for $APP_NAME."
    echo "                             This will initiate performance testing to simulate multiple users."
    echo ""
    echo "  --status                   Check the status of $APP_NAME installation."
    echo "                             Displays whether $APP_NAME is installed, running, or if there are any issues."
    echo ""
    echo "  --health-check             Perform a health check on $HOST_URL."
    echo "                             Verifies that the application is running correctly and responding to requests."
    echo ""
    echo "  --clean-backups            Clean up all backups of $APP_NAME."
    echo "                             This will delete all saved backup files to free up space."
    echo ""
    echo "  --logs                     Show server logs for $APP_NAME."
    echo "                             Displays the latest server logs, which can help in troubleshooting issues."
    echo "                             Press Ctrl+C to exit the log viewing session."
    echo ""
    echo " --installation-logs         Show installer logs for $APP_NAME."
    echo "                             Displays the logs generated during the installation process."
    echo "                             Press Ctrl+C to exit the log viewing session."
    echo ""
    echo "  --stop-server              Stop the $APP_NAME server."
    echo "                             This will stop the running server instance."
    echo ""
    echo " --install-latest            Update the code to the latest version."
    echo "                             This will pull the latest code from the Git repository."
    echo ""
    echo ""
    echo "  --help                     Display this help message."
    echo "                             Shows information about all available options and how to use them."
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
        --stop-server) stop_server; exit 0 ;;
        --fix) fix; exit 0 ;;
        --install-latest) ACTION="install_latest" ;;
        --open-app) open_browser; exit 0 ;;
        --fetch-github-releases) fetch_github_releases; exit 0 ;;
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
    install_latest) install_latest ;;
    open_browser) open_browser ;;
    fetch_github_releases) fetch_github_releases ;;
    *) echo "No action specified. Use --help for usage information." ;;
esac
