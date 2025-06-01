#!/bin/bash

# Script to download a file from a generic package in GitLab
# Uses Basic Authentication.

set -eo pipefail

# --- Configuration & Globals ---
GITLAB_URL=""
PROJECT_ID_OR_PATH=""
PACKAGE_NAME=""
PACKAGE_VERSION=""
FILE_NAME_IN_PACKAGE="" # Name of the file within the package to download
OUTPUT_FILE="" # Local path to save the downloaded file
USER_TOKEN=""
USERNAME="" # Username for Basic Auth (e.g., "oauth2" or your GitLab username)
DEBUG_MODE="false"

# --- Helper Functions ---

echo_error() {
    echo "[ERROR] $1" >&2
}

echo_warn() {
    echo "[WARN] $1" >&2
}

echo_info() {
    echo "[INFO] $1" >&2
}

echo_debug() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

usage() {
    echo "Usage: $0 -g <gitlab_url> -p <project_id_or_path> -n <package_name> -v <package_version> -F <file_name_in_package> -k <token> [-U <username>] [-o <output_file>] [-D]"
    echo ""
    echo "Parameters:"
    echo "  -g <gitlab_url>             : GitLab instance URL (e.g., gitlab.com)"
    echo "  -p <project_id_or_path>     : Project ID or URL-encoded path (e.g., 12345 or mygroup/myproject)"
    echo "  -n <package_name>           : Name of the generic package"
    echo "  -v <package_version>        : Version of the generic package"
    echo "  -F <file_name_in_package>   : Name of the file within the package to download"
    echo "  -k <token>                  : GitLab Token (PAT, Deploy Token, CI Job Token)"
    echo "  -U <username>               : (Optional) Username for Basic Auth. Defaults to 'oauth2'."
    echo "  -o <output_file>            : (Optional) Local path to save the downloaded file. Defaults to <file_name_in_package> in current directory."
    echo "  -D                          : (Optional) Enable debug mode (prints more verbose output)."
    echo ""
    echo "Example:"
    echo "  $0 -g gitlab.com -p mygroup/myproject -n mypackage -v 1.0.0 -F artifact.zip -k YOUR_GITLAB_TOKEN -o ./downloaded_artifact.zip"
    exit 1
}

# --- Argument Parsing ---
while getopts ":g:p:n:v:F:k:U:o:D" opt; do
    case ${opt} in
        g) GITLAB_URL=$OPTARG ;; 
        p) PROJECT_ID_OR_PATH=$OPTARG ;; 
        n) PACKAGE_NAME=$OPTARG ;; 
        v) PACKAGE_VERSION=$OPTARG ;; 
        F) FILE_NAME_IN_PACKAGE=$OPTARG ;; 
        k) USER_TOKEN=$OPTARG ;; 
        U) USERNAME=$OPTARG ;; 
        o) OUTPUT_FILE=$OPTARG ;; 
        D) DEBUG_MODE="true" ;; 
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

# --- Validate Required Parameters ---
if [ -z "$GITLAB_URL" ] || [ -z "$PROJECT_ID_OR_PATH" ] || [ -z "$PACKAGE_NAME" ] || [ -z "$PACKAGE_VERSION" ] || [ -z "$FILE_NAME_IN_PACKAGE" ] || [ -z "$USER_TOKEN" ]; then
    echo_error "Missing one or more required parameters."
    usage
fi

if [ -z "$USERNAME" ]; then
    echo_error "USERNAME is not set. Default is 'oauth2'. Use -U to override if needed."
    usage
fi

# Default OUTPUT_FILE if not provided
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="./${FILE_NAME_IN_PACKAGE##*/}" # Use basename of FILE_NAME_IN_PACKAGE in current dir
fi

# --- URL Encoding Function (simple version for paths) ---
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="$c" ;; # Safe characters
            * ) printf -v o '%%%02x' "'$c" ;; # Percent-encode others
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# --- Prepare Variables ---
GITLAB_URL_BASE="https://$GITLAB_URL"
PROJECT_IDENTIFIER_ENCODED=$(urlencode "$PROJECT_ID_OR_PATH")
PACKAGE_NAME_ENCODED=$(urlencode "$PACKAGE_NAME")
PACKAGE_VERSION_ENCODED=$(urlencode "$PACKAGE_VERSION")
FILE_NAME_IN_PACKAGE_ENCODED=$(urlencode "$FILE_NAME_IN_PACKAGE")

if [ "$DEBUG_MODE" = "true" ]; then
    echo_debug "[DEBUG] GITLAB_URL_BASE: $GITLAB_URL_BASE"
    echo_debug "[DEBUG] PROJECT_IDENTIFIER_ENCODED: $PROJECT_IDENTIFIER_ENCODED"
    echo_debug "[DEBUG] PACKAGE_NAME_ENCODED: $PACKAGE_NAME_ENCODED"
    echo_debug "[DEBUG] PACKAGE_VERSION_ENCODED: $PACKAGE_VERSION_ENCODED"
    echo_debug "[DEBUG] FILE_NAME_IN_PACKAGE_ENCODED: $FILE_NAME_IN_PACKAGE_ENCODED"
    echo_debug "[DEBUG] OUTPUT_FILE: $OUTPUT_FILE"
fi

# --- Main Download Logic ---
echo_info "Starting GitLab Generic Package Download..."

# Step 1: Setup Authentication Header
echo_info "Using Basic Authentication with username: $USERNAME"
basic_auth_credentials=$(echo -n "$USERNAME:$USER_TOKEN" | base64)
AUTH_HEADER_FOR_DOWNLOAD="Authorization: Basic $basic_auth_credentials"

# Step 2: Construct Download URL
DOWNLOAD_URL="$GITLAB_URL_BASE/api/v4/projects/$PROJECT_IDENTIFIER_ENCODED/packages/generic/$PACKAGE_NAME_ENCODED/$PACKAGE_VERSION_ENCODED/$FILE_NAME_IN_PACKAGE_ENCODED"

if [ "$DEBUG_MODE" = "true" ]; then
    echo_debug "[DEBUG] Download URL: $DOWNLOAD_URL"
fi

# Step 3: Perform Download
echo_info "Attempting to download $FILE_NAME_IN_PACKAGE to $OUTPUT_FILE..."

# Temporary file to store curl's stderr for detailed error messages if needed
CURL_STDERR_TMP=$(mktemp)

# Perform the download
# -sS for silent but show errors on stderr
# -w "%{http_code}" to output HTTP status code on stdout after completion
# -o "$OUTPUT_FILE" to save the body to the specified output file
# -k to skip SSL verification
# -L to follow redirects
HTTP_STATUS=$(curl -sS -w "%{http_code}" -k -L \
    -H "$AUTH_HEADER_FOR_DOWNLOAD" \
    -o "$OUTPUT_FILE" \
    "$DOWNLOAD_URL" 2> "$CURL_STDERR_TMP")

CURL_EXIT_CODE=$?

echo_debug "curl exit code: $CURL_EXIT_CODE"
echo_debug "HTTP status: $HTTP_STATUS"

if [ -s "$CURL_STDERR_TMP" ]; then # if stderr temp file is not empty
    echo_debug "curl stderr:"
    cat "$CURL_STDERR_TMP" >&2
fi

if [ "$CURL_EXIT_CODE" -eq 0 ] && [ "$HTTP_STATUS" -eq 200 ]; then
    echo_info "File '$FILE_NAME_IN_PACKAGE' downloaded successfully to '$OUTPUT_FILE'."
    echo_info "Download process complete."
    rm -f "$CURL_STDERR_TMP"
    exit 0
else
    echo_error "Download failed."
    if [ "$CURL_EXIT_CODE" -ne 0 ]; then
        echo_error "Curl command failed with exit code $CURL_EXIT_CODE."
        # stderr content already printed in debug mode if available
        if [ "$DEBUG_MODE" != "true" ] && [ -s "$CURL_STDERR_TMP" ]; then
             echo_error "Curl stderr:"
             cat "$CURL_STDERR_TMP" >&2
        elif [ "$DEBUG_MODE" != "true" ]; then
             echo_error "Curl stderr was empty or not captured."
        fi
    fi
    echo_error "HTTP status: $HTTP_STATUS."
    
    # Check if the downloaded file might contain an error message from the server
    if [ "$HTTP_STATUS" -ne 200 ] && [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        echo_error "The content of '$OUTPUT_FILE' might be an error message from the server."
        if [ "$DEBUG_MODE" = "true" ]; then
            echo_error "First 10 lines of '$OUTPUT_FILE':"
            head -n 10 "$OUTPUT_FILE" >&2
        fi
    elif [ "$HTTP_STATUS" -eq 404 ]; then
         echo_error "File not found on server (404). Verify package name, version, and file name."
    fi
    
    rm -f "$CURL_STDERR_TMP"
    echo_error "Download process failed."
    exit 1
fi
