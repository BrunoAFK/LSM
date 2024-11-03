#!/bin/bash

# Author: Bruno Pavelja - Bruno_AFK - Paveljame IT
# Description: Generates a list of scripts with their descriptions and ranks
# Version: 1.8

DEBUG=true  # Set to true to enable debugging
OUTPUT_FILE="./script_list.json"
SCRIPTS_DIR=("." "./scripts")
TEMP_FILE=$(mktemp)

# Debug function
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "\e[0;33m[DEBUG] $1\e[0m"
    fi
}

# Function to extract description from script
get_description() {
    local file="$1"
    grep -i "^#.*Description:" "$file" | sed 's/^#.*Description:\s*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -n 1
}

# Function to extract rank from script
get_rank() {
    local file="$1"
    grep -i "^#.*Rank:" "$file" | sed 's/^#.*Rank:\s*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -n 1
}

# Initialize array to store script entries
declare -a script_entries

# Process each script file from both directories
for dir in "${SCRIPTS_DIR[@]}"; do
    if [ -d "$dir" ]; then
        debug_log "Searching in directory: $dir"
        
        # Find all regular files, excluding hidden files and generate_script_list.sh
        while IFS= read -r script; do
            # Check if first line contains "bash"
            if head -n 1 "$script" | grep -q "bash"; then
                debug_log "Found bash script: $script"
                
                script_name=$(basename "$script")
                description=$(get_description "$script")
                rank=$(get_rank "$script")

                debug_log "Script name: $script_name"
                debug_log "Description found: $description"
                debug_log "Rank found: $rank"

                # If no rank is found, mark as "Unranked"
                if [ -z "$rank" ]; then
                    rank="Unranked"
                    debug_log "No rank found, setting to: $rank"
                fi

                # If no description is found, mark as "No description available"
                if [ -z "$description" ]; then
                    description="No description available"
                    debug_log "No description found, setting to: $description"
                fi

                # Create JSON entry and add to array
                entry=$(cat <<EOF
    {
      "name": "$script_name",
      "path": "$script",
      "rank": "$rank",
      "description": "$description"
    }
EOF
)
                script_entries+=("$entry")
                debug_log "Added entry for: $script_name"
            else
                debug_log "Skipping non-bash file: $script"
            fi
        done < <(find "$dir" -maxdepth 1 -type f ! -name ".*" ! -name "generate_script_list.sh")
        
        debug_log "Finished processing directory: $dir"
    else
        debug_log "Directory not found: $dir"
    fi
done

# Write the JSON file with proper formatting
{
    echo "{"
    echo "  \"generated_date\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
    echo "  \"scripts\": ["
    
    # Join array elements with commas
    for i in "${!script_entries[@]}"; do
        if [ $i -eq $((${#script_entries[@]} - 1)) ]; then
            # Last element - no comma
            echo "${script_entries[$i]}"
        else
            # Not last element - add comma
            echo "${script_entries[$i]},"
        fi
    done
    
    echo "  ]"
    echo "}"
} > "$OUTPUT_FILE"

# Validate JSON
if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
        echo -e "\e[1;32m✅ Script list has been generated and validated in $OUTPUT_FILE\e[0m"
    else
        echo -e "\e[1;31m❌ Generated JSON is invalid! Please check the output.\e[0m"
        exit 1
    fi
else
    echo -e "\e[1;33m⚠️  JSON validation skipped (jq not installed)\e[0m"
fi

# Cleanup
rm -f "$TEMP_FILE"