#!/usr/bin/env bash

# Git Tracer - Track git commits across multiple repositories
# Version: 1.0.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/init.conf"

# Global variables
USERNAME=""
DATE_START=""
DATE_END=""
Q_NUMBER=""
SOURCE_PATH=""
OUTPUT_FILE=""
SHOW_WARNING=false
WARNING_MESSAGE=""
TEMP_DIR=""

# Load configuration file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        # Set defaults if config doesn't exist
        DEFAULT_USERNAME=""
        DEFAULT_SOURCE_PATH="."
        REPO_INCLUDE_PATTERNS="*"
        REPO_EXCLUDE_PATTERNS=""
        MAX_PARALLEL_JOBS=5
        GIT_LOG_OPTIONS=""
        OUTPUT_DIR="./output"
        SHOW_PROGRESS=true
        VERBOSE=false
    fi
}

# Display usage information
usage() {
    cat <<EOF
Git Tracer - Track git commits across multiple repositories

Usage: $0 [OPTIONS]

Options:
    -u, --username <name>       Git author username (default: current git user)
    -s, --dateStart <date>      Start date in YYYY-MM-DD format
    -e, --dateEnd <date>        End date in YYYY-MM-DD format
    -q, --qNumber <-4 to 4>     Quarter number: 0=current, 1-4=Q1-Q4, -1 to -4=previous quarters
    -p, --sourcePath <path>     Root path to search for repos (default: current directory)
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose mode

Examples:
    $0                                  # Current quarter, current user
    $0 -q 0                             # Current quarter (explicit)
    $0 -q 2                             # Q2 of current year
    $0 -q -1                            # Previous quarter
    $0 -u johndoe                       # Current quarter for specific user
    $0 -s 2025-01-01 -e 2025-12-31      # Custom date range
    $0 -q -1 -u johndoe -p ~/workspace  # Previous quarter, custom user and path

EOF
    exit 0
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -s|--dateStart)
                DATE_START="$2"
                shift 2
                ;;
            -e|--dateEnd)
                DATE_END="$2"
                shift 2
                ;;
            -q|--qNumber)
                Q_NUMBER="$2"
                shift 2
                ;;
            -p|--sourcePath)
                SOURCE_PATH="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Error: Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate qNumber if provided
    if [[ -n "$Q_NUMBER" ]]; then
        if ! [[ "$Q_NUMBER" =~ ^-?[0-9]+$ ]] || [[ "$Q_NUMBER" -lt -4 ]] || [[ "$Q_NUMBER" -gt 4 ]]; then
            echo "Error: qNumber must be between -4 and 4"
            exit 1
        fi
    fi

    # Set defaults
    SOURCE_PATH="${SOURCE_PATH:-$DEFAULT_SOURCE_PATH}"
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
}

# Get current git user
get_current_git_user() {
    local user=""

    if [[ -n "$USERNAME" ]]; then
        echo "$USERNAME"
        return
    fi

    # Try git config user.name
    user=$(git config user.name 2>/dev/null || true)
    if [[ -n "$user" ]]; then
        echo "$user"
        return
    fi

    # Fallback to git config user.email
    user=$(git config user.email 2>/dev/null || true)
    if [[ -n "$user" ]]; then
        echo "$user"
        return
    fi

    echo "Error: Could not determine git username. Please provide --username or configure git."
    exit 1
}

# Calculate quarter dates
calculate_quarter_dates() {
    local qnum="$1"
    local current_year current_month current_quarter
    local target_year target_quarter

    current_year=$(date +%Y)
    current_month=$(date +%-m)
    current_quarter=$(( (current_month - 1) / 3 + 1 ))

    if [[ -z "$qnum" ]] || [[ "$qnum" -eq 0 ]]; then
        # Current quarter
        target_year=$current_year
        target_quarter=$current_quarter
    elif [[ "$qnum" -gt 0 ]]; then
        # Positive qNumber (1-4)
        if [[ "$qnum" -gt "$current_quarter" ]]; then
            # Future quarter in current year, use previous year
            target_year=$((current_year - 1))
            target_quarter=$qnum
            SHOW_WARNING=true
            WARNING_MESSAGE="⚠️  WARNING: Q$qnum $current_year hasn't occurred yet. Scanning Q$qnum $target_year instead."
        else
            target_year=$current_year
            target_quarter=$qnum
        fi
    else
        # Negative qNumber
        local quarters_back=$(( -qnum ))
        local total_quarters=$(( current_year * 4 + current_quarter ))
        local target_total=$(( total_quarters - quarters_back ))
        target_year=$(( (target_total - 1) / 4 ))
        target_quarter=$(( ((target_total - 1) % 4) + 1 ))
    fi

    # Calculate start and end dates for the quarter
    case $target_quarter in
        1) DATE_START="$target_year-01-01"; DATE_END="$target_year-03-31" ;;
        2) DATE_START="$target_year-04-01"; DATE_END="$target_year-06-30" ;;
        3) DATE_START="$target_year-07-01"; DATE_END="$target_year-09-30" ;;
        4) DATE_START="$target_year-10-01"; DATE_END="$target_year-12-31" ;;
    esac
}

# Find all git repositories
find_git_repos() {
    local source_path="$1"
    local repos=()

    if [[ ! -d "$source_path" ]]; then
        echo "Error: Source path does not exist: $source_path"
        exit 1
    fi

    # Find all .git directories
    while IFS= read -r -d '' git_dir; do
        local repo_path=$(dirname "$git_dir")
        local repo_name=$(basename "$repo_path")

        # Apply include patterns
        local include=false
        for pattern in $REPO_INCLUDE_PATTERNS; do
            if [[ "$repo_name" == $pattern ]]; then
                include=true
                break
            fi
        done

        # Apply exclude patterns
        if [[ "$include" == true ]]; then
            for pattern in $REPO_EXCLUDE_PATTERNS; do
                if [[ "$repo_name" == $pattern ]]; then
                    include=false
                    break
                fi
            done
        fi

        if [[ "$include" == true ]]; then
            repos+=("$repo_path")
        fi
    done < <(find "$source_path" -type d -name ".git" -print0 2>/dev/null)

    printf '%s\n' "${repos[@]}"
}

# Detect which branch to scan
detect_repo_branch() {
    local repo_path="$1"
    local branch=""
    local has_changes=false

    # Check for uncommitted changes
    if [[ -n "$(git -C "$repo_path" status --porcelain 2>/dev/null)" ]]; then
        has_changes=true
    fi

    if [[ "$has_changes" == true ]]; then
        # Use current branch if repo has changes
        branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
        echo "$branch (has changes)"
    else
        # Try to use origin/HEAD
        branch=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/||' || echo "")

        if [[ -z "$branch" ]]; then
            # Fallback to current branch
            branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
        fi

        echo "$branch"
    fi
}

# Get commits for a repository
get_commits_for_repo() {
    local repo_path="$1"
    local author="$2"
    local date_start="$3"
    local date_end="$4"
    local branch="$5"

    # Remove "(has changes)" suffix if present
    local clean_branch=$(echo "$branch" | sed 's/ (has changes)$//')

    git -C "$repo_path" log "$clean_branch" \
        --author="$author" \
        --since="$date_start" \
        --until="$date_end" \
        --no-merges \
        --pretty=format:"%H|%ai|%s%n%b" \
        --date=iso \
        $GIT_LOG_OPTIONS 2>/dev/null || true
}

# Process repository asynchronously
process_repo_async() {
    local repo_path="$1"
    local author="$2"
    local date_start="$3"
    local date_end="$4"
    local temp_file="$5"

    local repo_name=$(basename "$repo_path")
    local branch=$(detect_repo_branch "$repo_path")
    local commits=$(get_commits_for_repo "$repo_path" "$author" "$date_start" "$date_end" "$branch")
    local commit_count=0

    # Count commits (each commit starts with a line containing a hash)
    if [[ -n "$commits" ]]; then
        commit_count=$(echo "$commits" | grep -c "^[a-f0-9]\{40\}|" || true)
    fi

    # Only write to temp file if there are commits
    if [[ "$commit_count" -gt 0 ]]; then
        {
            echo "## $repo_name"
            echo "**Branch scanned**: $branch"
            echo "**Commits in this repository**: $commit_count"
            echo ""

            while IFS='|' read -r hash date message; do
                if [[ -n "$hash" ]]; then
                    # Format the date
                    local formatted_date=$(echo "$date" | cut -d' ' -f1,2)
                    echo "- **$hash** | $formatted_date | $message"
                fi
            done <<< "$commits"

            echo ""
        } > "$temp_file"
    else
        # Create empty temp file to indicate repo was processed but had no commits
        touch "$temp_file.skipped"
    fi
}

# Initialize markdown file
initialize_markdown_file() {
    local output_file="$1"
    local author="$2"
    local date_start="$3"
    local date_end="$4"

    cat > "$output_file" <<EOF
# Git Commits Report

**Author**: $author
**Period**: $date_start to $date_end
**Generated**: $(date '+%Y-%m-%d %H:%M:%S')
**Total Commits**: PLACEHOLDER_TOTAL
**Repositories Scanned**: PLACEHOLDER_REPOS

---

EOF
}

# Update total counts in markdown file
update_total_counts() {
    local output_file="$1"
    local total_commits="$2"
    local total_repos="$3"

    # Replace placeholders
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/PLACEHOLDER_TOTAL/$total_commits/" "$output_file"
        sed -i '' "s/PLACEHOLDER_REPOS/$total_repos/" "$output_file"
    else
        # Linux
        sed -i "s/PLACEHOLDER_TOTAL/$total_commits/" "$output_file"
        sed -i "s/PLACEHOLDER_REPOS/$total_repos/" "$output_file"
    fi

    # Add completion timestamp
    echo "" >> "$output_file"
    echo "---" >> "$output_file"
    echo "" >> "$output_file"
    echo "**Scan completed at**: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
}

# Display execution summary
display_execution_summary() {
    local repos=("$@")
    local repo_count=${#repos[@]}

    echo "╔════════════════════════════════════════════════════════╗"
    echo "║          Git Tracer - Execution Summary              ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "Author:           $USERNAME"
    echo "Date Range:       $DATE_START to $DATE_END"
    echo "Source Path:      $SOURCE_PATH"
    echo "Repositories:     $repo_count found"
    echo "Max Parallel:     $MAX_PARALLEL_JOBS"
    echo "Output File:      $OUTPUT_FILE"
    echo ""

    if [[ "$SHOW_WARNING" == true ]]; then
        echo "$WARNING_MESSAGE"
        echo ""
    fi

    read -p "Press Enter to continue or Ctrl+C to cancel..."
}

# Show progress
show_progress() {
    local completed="$1"
    local total="$2"
    local repo_name="$3"

    if [[ "$SHOW_PROGRESS" == true ]]; then
        local percent=$((completed * 100 / total))
        echo "[$completed/$total] ($percent%) Scanning: $repo_name"
    fi
}

# Main function
main() {
    echo "Git Tracer - Starting..."
    echo ""

    # Load configuration
    load_config

    # Parse arguments
    parse_arguments "$@"

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo "Error: git command not found. Please install git."
        exit 1
    fi

    # Get username
    USERNAME=$(get_current_git_user)

    # Calculate or use provided date range
    if [[ -z "$DATE_START" ]] || [[ -z "$DATE_END" ]]; then
        calculate_quarter_dates "$Q_NUMBER"
    fi

    # Find all git repositories
    echo "Searching for git repositories in: $SOURCE_PATH"
    mapfile -t repos < <(find_git_repos "$SOURCE_PATH")

    if [[ ${#repos[@]} -eq 0 ]]; then
        echo "No git repositories found in: $SOURCE_PATH"
        exit 1
    fi

    echo "Found ${#repos[@]} repositories"
    echo ""

    # Create output filename
    OUTPUT_FILE="$SCRIPT_DIR/$OUTPUT_DIR/${DATE_START}x${DATE_END}.${USERNAME}.md"

    # Display execution summary
    display_execution_summary "${repos[@]}"

    echo ""
    echo "Starting scan..."

    # Create temp directory
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/git-tracer.XXXXXX")
    trap "rm -rf '$TEMP_DIR'" EXIT

    # Initialize markdown file
    initialize_markdown_file "$OUTPUT_FILE" "$USERNAME" "$DATE_START" "$DATE_END"

    # Process repositories in parallel
    local pids=()
    local active_jobs=0
    local completed=0
    declare -A processed_pids

    for i in "${!repos[@]}"; do
        local repo="${repos[$i]}"
        local repo_name=$(basename "$repo")
        local temp_file="$TEMP_DIR/repo_$(printf "%03d" $i)_$(echo "$repo_name" | tr ' ' '_').md"

        # Wait if max parallel jobs reached
        while [[ $active_jobs -ge $MAX_PARALLEL_JOBS ]]; do
            # Check for completed jobs
            for pid in "${pids[@]}"; do
                if [[ -z "${processed_pids[$pid]:-}" ]] && ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid" 2>/dev/null || true
                    processed_pids[$pid]=1
                    ((active_jobs--)) || true
                    ((completed++)) || true
                fi
            done
            sleep 0.1
        done

        # Start background process
        process_repo_async "$repo" "$USERNAME" "$DATE_START" "$DATE_END" "$temp_file" &
        local pid=$!
        pids+=("$pid")
        ((active_jobs++)) || true

        show_progress $completed ${#repos[@]} "$repo_name"
    done

    # Wait for all remaining jobs to complete
    for pid in "${pids[@]}"; do
        if [[ -z "${processed_pids[$pid]:-}" ]]; then
            wait "$pid" 2>/dev/null || true
            ((completed++)) || true
            show_progress $completed ${#repos[@]} "..."
        fi
    done

    echo ""
    echo "Merging results..."

    # Merge all temp files into final output
    local total_commits=0
    local repos_with_commits=0
    for temp_file in "$TEMP_DIR"/repo_*.md; do
        if [[ -f "$temp_file" ]] && [[ ! "$temp_file" =~ \.skipped$ ]]; then
            cat "$temp_file" >> "$OUTPUT_FILE"
            # Count commits in this file
            local count=$(grep -c "^- \*\*[a-f0-9]\{40\}\*\*" "$temp_file" || true)
            total_commits=$((total_commits + count))
            ((repos_with_commits++)) || true
        fi
    done

    # Update total counts
    update_total_counts "$OUTPUT_FILE" "$total_commits" "$repos_with_commits"

    echo ""
    echo "✓ Scan complete!"
    echo ""
    echo "Summary:"
    echo "  Total Commits: $total_commits"
    echo "  Repositories with Commits: $repos_with_commits / ${#repos[@]}"
    echo "  Output File: $OUTPUT_FILE"
    echo ""
}

# Run main function
main "$@"
