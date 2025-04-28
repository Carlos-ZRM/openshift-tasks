#!/bin/bash

# Default values
num_requests=5
verbose_mode=false
output_file="output-$(date +"%y-%d-%m-%H-%M-%S").log"


# List of sites to test
sites=("registry.redhat.io"
    "docker.io"
    "access.redhat.com"
    "registry.access.redhat.com"
    "quay.io"
    "cdn.quay.io"
    "cdn01.quay.io"
    "cdn02.quay.io"
    "cdn03.quay.io"
    "cdn04.quay.io"
    "cdn05.quay.io"
    "cdn06.quay.io"
    "sso.redhat.com"
    "cert-api.access.redhat.com"
    "api.access.redhat.com"
    "infogw.api.openshift.com"
    "console.redhat.com"
    "api.openshift.com"
    "console.redhat.com"
    "mirror.openshift.com"
    "registry.connect.redhat.com"
    "repo.maven.apache.org"
    "repo1.maven.org"

    )


# Function to display help
function display_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -n, --num-requests <number>  Number of curl requests to perform (default: 20)"
  echo "  -v, --verbose                Enable verbose mode for curl"
  echo "  -o, --output-file <file>     Write output to a file instead of stdout"
  echo "  -h, --help                   Display this help message"
  echo "example: $0 -n 10 -v -o output.log"
  exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--num-requests)
      num_requests="$2"
      shift 2
      ;;
    -v|--verbose)
      verbose_mode=true
      shift
      ;;
    -o|--output-file)
      output_file="$2"
      shift 2
      ;;
    -h|--help)
      display_help
      ;;
    *)
      echo "Unknown option: $1"
      display_help
      ;;
  esac
done

# Redirect output to file if specified
if [[ -n "$output_file" ]]; then
  exec > >(tee -a "$output_file") 2>&1
fi

# Get the current date with seconds in YY-DD-MM-HOUR-MIN-SEC format
current_date=$(date +"%y-%d-%m-%H-%M-%S")
echo "Script started at: $current_date"

# Loop through each site
for site in "${sites[@]}"; do
  echo "Testing site: $site"
  
  # Initialize an associative array to count HTTP codes
  declare -A http_codes
  
  # Perform the specified number of curl requests
  for ((i = 1; i <= num_requests; i++)); do
    
    # Check if verbose mode is enabled

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$site")
    if [ "$verbose_mode" = true ]; then
      echo "Reg $i to $site: $http_code"
    fi
    # Increment the count for the HTTP code
    ((http_codes[$http_code]++))
  done
  
  # Print the results for the site
  echo "HTTP code counts for $site:"
  for code in "${!http_codes[@]}"; do
    echo "  $code: ${http_codes[$code]}"
  done
  
  # Clear the associative array for the next site
  unset http_codes
done