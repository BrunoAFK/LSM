#!/bin/bash

# Author: Bruno Pavelja - Bruno_AFK - Paveljame IT
# Description: Generates a list of scripts with their descriptions and ranks
# Version: 1.0

OUTPUT_FILE="./script_list.txt"
SCRIPTS_DIR="./scripts"

echo "# Script List" > "$OUTPUT_FILE"
echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE"
echo "----------------------------------------" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

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

# Process each script file
find "$SCRIPTS_DIR" -type f -executable -o -name "*.sh" | while read -r script; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        description=$(get_description "$script")
        rank=$(get_rank "$script")

        # If no rank is found, mark as "Unranked"
        if [ -z "$rank" ]; then
            rank="Unranked"
        fi

        # If no description is found, mark as "No description available"
        if [ -z "$description" ]; then
            description="No description available"
        fi

        echo "Script: $script_name" >> "$OUTPUT_FILE"
        echo "Rank: $rank" >> "$OUTPUT_FILE"
        echo "Description: $description" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
    fi
done

echo -e "\e[1;32m✅ Script list has been generated in $OUTPUT_FILE\e[0m" 