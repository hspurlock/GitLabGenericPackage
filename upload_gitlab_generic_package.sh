#!/bin/bash

# Script to upload a file as a generic package to GitLab

set -eo pipefail

# --- Configuration & Globals ---
GITLAB_URL=""
PROJECT_ID_OR_PATH=""
PACKAGE_NAME=""
PACKAGE_VERSION=""
FILE_TO_UPLOAD=""
USER_TOKEN=""
USERNAME=""

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

usage() {
    echo "Usage: $0 -g <gitlab_url> -p <project_id_or_path> -n <package_name> -v <package_version> -f <file_to_upload> -k <token> [-U <username>] [-A <auth_realm>] [-S <auth_service>] [--scope <jwt_scope>] [-D]"
    echo ""
    echo "Parameters:"
    echo "  -g <gitlab_url>          : GitLab instance URL (e.g., gitlab.com, gitlab.mycompany.com)"
    echo "  -p <project_id_or_path>  : Project ID or URL-encoded path (e.g., 12345 or mygroup/myproject)"
    echo "  -n <package_name>        : Name of the generic package"
    echo "  -v <package_version>     : Version of the generic package"
    echo "  -f <file_to_upload>      : Path to the local file to upload"
    echo "  -k <token>               : GitLab Token (PAT, Deploy Token, CI Job Token)"
    echo "  -U <username>            : (Optional) Username for Basic Auth"

    echo "  -D                       : (Optional) Enable debug mode (prints more verbose output)."
    echo ""
    echo "Example:"
    echo "  $0 -g gitlab.com -p mygroup/myproject -n mypackage -v 1.0.0 -f ./artifact.zip -k YOUR_GITLAB_TOKEN"
    exit 1
}

# --- Argument Parsing ---
while getopts ":g:p:n:v:f:k:U:D" opt; do
    case ${opt} in
        g) GITLAB_URL=$OPTARG ;; 
        p) PROJECT_ID_OR_PATH=$OPTARG ;; 
        n) PACKAGE_NAME=$OPTARG ;; 
        v) PACKAGE_VERSION=$OPTARG ;; 
        f) FILE_TO_UPLOAD=$OPTARG ;; 
        k) USER_TOKEN=$OPTARG ;; 
        U) USERNAME=$OPTARG ;; 
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
shift $((OPTIND -1))

# Validate mandatory parameters
if [ -z "$GITLAB_URL" ] || [ -z "$PROJECT_ID_OR_PATH" ] || [ -z "$PACKAGE_NAME" ] || [ -z "$PACKAGE_VERSION" ] || [ -z "$FILE_TO_UPLOAD" ] || [ -z "$USER_TOKEN" ]; then
    echo_error "Missing one or more mandatory parameters."
    usage
fi

if [ ! -f "$FILE_TO_UPLOAD" ]; then
    echo_error "File to upload not found: $FILE_TO_UPLOAD"
    exit 1
fi

# Ensure jq is installed for URL encoding
if ! command -v jq &> /dev/null; then
    echo_error "jq is not installed. Please install jq to use this script."
    exit 1
fi

# Normalize GitLab URL: remove scheme, remove trailing slashes, then add https://
GITLAB_URL_NO_SCHEME=$(echo "$GITLAB_URL" | sed -e 's|^[^/]*//||' -e 's:/*$::')
GITLAB_URL_BASE="https://$GITLAB_URL_NO_SCHEME"

# URL Encode components
PROJECT_IDENTIFIER_ENCODED=$(printf "%s" "$PROJECT_ID_OR_PATH" | jq -sRr @uri)
PACKAGE_NAME_ENCODED=$(printf "%s" "$PACKAGE_NAME" | jq -sRr @uri)
PACKAGE_VERSION_ENCODED=$(printf "%s" "$PACKAGE_VERSION" | jq -sRr @uri)
UPLOAD_FILE_BASENAME=$(basename "$FILE_TO_UPLOAD")
UPLOAD_FILE_BASENAME_ENCODED=$(printf "%s" "$UPLOAD_FILE_BASENAME" | jq -sRr @uri)

if [ "$DEBUG_MODE" = "true" ]; then
    echo_info "[DEBUG] GITLAB_URL_BASE: $GITLAB_URL_BASE"
    echo_info "[DEBUG] PROJECT_IDENTIFIER_ENCODED: $PROJECT_IDENTIFIER_ENCODED"
    echo_info "[DEBUG] PACKAGE_NAME_ENCODED: $PACKAGE_NAME_ENCODED"
    echo_info "[DEBUG] PACKAGE_VERSION_ENCODED: $PACKAGE_VERSION_ENCODED"
    echo_info "[DEBUG] UPLOAD_FILE_BASENAME_ENCODED: $UPLOAD_FILE_BASENAME_ENCODED"
fi



# --- Main Upload Logic ---
echo_info "Starting GitLab Generic Package Upload..."

# Step 1: Setup Authentication Header
if [ -z "$USERNAME" ]; then # USERNAME is defaulted or can be set by -U
    echo_error "USERNAME is not set. Basic Authentication requires a username."
    usage # Exits
fi
if [ -z "$USER_TOKEN" ]; then # USER_TOKEN must be set by -k
    echo_error "USER_TOKEN is not set. Basic Authentication requires a token/password."
    usage # Exits
fi

echo_info "Using Basic Authentication with username: $USERNAME"
basic_auth_credentials=$(echo -n "$USERNAME:$USER_TOKEN" | base64)
AUTH_HEADER_FOR_UPLOAD="Authorization: Basic $basic_auth_credentials"

# Step 2: Construct Upload URL
UPLOAD_URL="$GITLAB_URL_BASE/api/v4/projects/$PROJECT_IDENTIFIER_ENCODED/packages/generic/$PACKAGE_NAME_ENCODED/$PACKAGE_VERSION_ENCODED/$UPLOAD_FILE_BASENAME_ENCODED"
if [ "$DEBUG_MODE" = "true" ]; then
    echo_info "[DEBUG] Final UPLOAD_URL: $UPLOAD_URL"
else
    echo_info "Upload URL: $UPLOAD_URL"
fi

# Step 3: Perform Upload
echo_info "Attempting upload..."

curl_cmd_args=(
    --show-error # Shows curl's own errors if any
    -k # Skip SSL verification
    -H "$AUTH_HEADER_FOR_UPLOAD"
    -H "Content-Type: application/octet-stream"
    -X PUT
    --upload-file "$FILE_TO_UPLOAD"
    "$UPLOAD_URL"
)

HTTP_STATUS=$(curl --silent --write-out "%{http_code}" --output /dev/null "${curl_cmd_args[@]}")

echo_info "Upload attempt finished with HTTP status: $HTTP_STATUS"

if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
    echo_info "File uploaded successfully!"
    echo_info "Upload process complete."
    exit 0
else
    echo_error "Upload failed with HTTP status: $HTTP_STATUS."
    if [ "$DEBUG_MODE" = "true" ]; then
        echo_error "Showing full verbose output from curl for diagnostics:"
        curl -v "${curl_cmd_args[@]}" # -k is already in curl_cmd_args from its definition
    fi
    echo_error "Upload process failed."
    exit 1
fi
