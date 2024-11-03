#!/bin/bash

# Author: Bruno Pavelja - Bruno_AFK - Paveljame IT
# Description: Generates a list of scripts with their descriptions and ranks
# Version: 1.6

DEBUG=true  # Set to true to enable debugging
OUTPUT_FILE="./script_list.json"
SCRIPTS_DIR=("." "./scripts")

# Debug function
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "\e[0;33m[DEBUG] $1\e[0m"
    fi
}

echo "{" > "$OUTPUT_FILE"
echo "  \"generated_date\": \"$(date '+%Y-%m-%d %H:%M:%S')\"," >> "$OUTPUT_FILE"
echo "  \"scripts\": [" >> "$OUTPUT_FILE"

# Function to extract description from script
get_description() {
    local file="$1"
    grep -i "^#.*Description:" "$file" | sed 's/^#.*Description:\s*//' | head -n 1
}

# Function to extract rank from script
get_rank() {
    local file="$1"
    grep -i "^#.*Rank:" "$file" | sed 's/^#.*Rank:\s*//' | head -n 1
}

# Process each script file from both directories
for dir in "${SCRIPTS_DIR[@]}"; do
    if [ -d "$dir" ]; then
        debug_log "Searching in directory: $dir"
        
        # Find all regular files, excluding hidden files and generate_script_list.sh
        find "$dir" -maxdepth 1 -type f ! -name ".*" ! -name "generate_script_list.sh" | while read -r script; do
            # Check if first line contains "bash"
            if head -n 1 "$script" | grep -q "bash"; then
                debug_log "Found bash script: $script"
                debug_log "First line: $(head -n 1 "$script")"
                
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

                # Write in JSON format
                debug_log "Writing to output file: $OUTPUT_FILE"
                echo "    {" >> "$OUTPUT_FILE"
                echo "      \"name\": \"$script_name\"," >> "$OUTPUT_FILE"
                echo "      \"path\": \"$script\"," >> "$OUTPUT_FILE"
                echo "      \"rank\": \"$rank\"," >> "$OUTPUT_FILE"
                echo "      \"description\": \"$description\"" >> "$OUTPUT_FILE"
                echo "    }," >> "$OUTPUT_FILE"
            else
                debug_log "Skipping non-bash file: $script"
            fi
        done
        
        debug_log "Finished processing directory: $dir"
    else
        debug_log "Directory not found: $dir"
    fi
done

# Fix the sed command for macOS
# Remove the last comma and close the JSON structure
sed -i '' '$ s/,$//' "$OUTPUT_FILE"

echo "  ]" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

echo -e "\e[1;32m✅ Script list has been generated in $OUTPUT_FILE\e[0m" 