# Git Tracer

A cross-platform Bash script to track and document git commits across multiple repositories by user and date range, with quarterly filtering support and parallel processing.

## Features

- Track commits across multiple repositories simultaneously
- Flexible date filtering with quarter-based shortcuts
- Negative quarter numbers to look back in time
- Asynchronous parallel processing for fast scanning
- Smart branch detection (origin/HEAD or current branch if dirty)
- Automatic merge commit exclusion
- Configurable defaults via init.conf
- Cross-platform support (Mac, Linux, Windows Git Bash/WSL)
- Pre-execution summary with confirmation

## Requirements

- `git` command-line tool
- Bash shell (version 4.0 or higher recommended)

## Installation

1. Clone or download this repository
2. Navigate to the `scripts.git-tracer` directory
3. Make the script executable (if not already):
   ```bash
   chmod +x run.sh
   ```
4. (Optional) Configure defaults in [init.conf](./init.conf)

## Configuration

The script uses an `init.conf` configuration file to set default values. All settings can be overridden via command-line arguments.

### Configuration Priority

Settings are applied in the following order (later overrides earlier):
1. Configuration file ([init.conf](./init.conf))
2. Environment variables
3. Command-line arguments

### Example Configurations

**For a specific workspace:**
```bash
DEFAULT_SOURCE_PATH="$HOME/workspace"
REPO_INCLUDE_PATTERNS="ixicale* another_example* johndoe*"
```

**Exclude certain repositories:**
```bash
REPO_EXCLUDE_PATTERNS="archived-* test-* node_modules"
```

**Increase parallel processing:**
```bash
MAX_PARALLEL_JOBS=10
```

## Usage

### Basic Syntax

```bash
./run.sh [OPTIONS]
```

### Options

| Short | Long | Type | Description |
|-------|------|------|-------------|
| `-u` | `--username <name>` | string | Git author username (default: current git user) |
| `-s` | `--dateStart <date>` | YYYY-MM-DD | Start date for commit search |
| `-e` | `--dateEnd <date>` | YYYY-MM-DD | End date for commit search |
| `-q` | `--qNumber <-4 to 4>` | integer | Quarter number (see Quarter Logic below) |
| `-p` | `--sourcePath <path>` | string | Root path to search for repos |
| `-v` | `--verbose` | flag | Enable verbose output |
| `-h` | `--help` | flag | Show help message |

### Quarter Logic

The `qNumber` parameter provides convenient shortcuts for date ranges:

| qNumber | Description | Example (if today is Jan 19, 2026) |
|---------|-------------|-------------------------------------|
| 0 or omitted | Current quarter | Q1 2026 (Jan 1 - Mar 31, 2026) |
| 1 | Q1 (Jan-Mar) | Q1 2026 |
| 2 | Q2 (Apr-Jun) | Q2 2025 (warns if Q2 2026 not reached) |
| 3 | Q3 (Jul-Sep) | Q3 2025 |
| 4 | Q4 (Oct-Dec) | Q4 2025 |
| -1 | 1 quarter ago | Q4 2025 |
| -2 | 2 quarters ago | Q3 2025 |
| -3 | 3 quarters ago | Q2 2025 |
| -4 | 4 quarters ago | Q1 2025 |

**Note:** If you specify a future quarter (e.g., Q2 when currently in Q1), the script will use the previous year and display a warning.

## Examples

### Basic Usage

```bash
# Scan current quarter for current user
./run.sh

# Explicitly specify current quarter
./run.sh -q 0
# or
./run.sh --qNumber 0
```

### Specific User

```bash
# Current quarter for a specific user (short option)
./run.sh -u johndoe

# Using long option
./run.sh --username johndoe
```

### Quarter-Based Scanning

```bash
# Q2 of current year (or previous year if Q2 hasn't occurred yet)
./run.sh -q 2

# Previous quarter
./run.sh -q -1

# 4 quarters ago (1 year back)
./run.sh -q -4
```

### Custom Date Range

```bash
# Scan entire year (short options)
./run.sh -s 2025-01-01 -e 2025-12-31

# Scan specific month (long options)
./run.sh --dateStart 2026-01-01 --dateEnd 2026-01-31
```

### Custom Source Path

```bash
# Scan repositories in a specific directory (short option)
./run.sh -p ~/projects

# Scan with specific user and path (mixed short/long)
./run.sh -u johndoe --sourcePath ~/workspace/projects
```

### Combined Options

```bash
# Previous quarter for specific user in custom path (short options)
./run.sh -q -1 -u johndoe -p ~/workspace

# Same with long options
./run.sh --qNumber -1 --username johndoe --sourcePath ~/workspace
```

## Output

### Output Location

By default, output files are saved to `./output/`

### Output File Format

Filename: `{dateStart}x{dateEnd}.{username}.md`

Example: `2026-01-01x2026-03-31.johndoe.md`

### Output Structure

The generated Markdown file includes:

1. **Header**: Author, date range, generation timestamp, total commits, repositories scanned
2. **Repository Sections**: Each repository as a level 2 heading
   - Branch that was scanned
   - Number of commits in that repository
   - List of commits with full hash, date, and message
3. **Footer**: Scan completion timestamp

### Example Output

```markdown
# Git Commits Report

**Author**: johndoe
**Period**: 2026-01-01 to 2026-03-31
**Generated**: 2026-01-19 10:30:15
**Total Commits**: 47
**Repositories Scanned**: 3

---

## my-project
**Branch scanned**: origin/main
**Commits in this repository**: 23

- **a1b2c3d4e5f6...** | 2026-01-15 14:23:45 | Add new feature for user authentication
- **f6e5d4c3b2a1...** | 2026-01-14 09:15:30 | Fix bug in login flow

## another-repo
**Branch scanned**: feature-branch (has changes)
**Commits in this repository**: 15

- **9876543210ab...** | 2026-01-18 11:45:22 | Update documentation

---

**Scan completed at**: 2026-01-19 10:30:45
```

## Branch Detection

The script uses smart branch detection:

- **Clean repositories**: Scans from `origin/HEAD` (remote default branch)
- **Dirty repositories** (uncommitted changes): Scans from current branch
- Output shows which branch was scanned and if the repo had changes

## Merge Commits

Merge commits are automatically excluded from all scans using the `--no-merges` flag.

## Parallel Processing

The script processes multiple repositories in parallel for improved performance:

- Default: 5 concurrent repository scans
- Configurable via `MAX_PARALLEL_JOBS` in `init.conf`
- Progress is displayed in real-time

## Troubleshooting

### No repositories found

**Problem**: Script reports "No git repositories found"

**Solutions**:
- Check that the source path contains git repositories
- Verify `REPO_INCLUDE_PATTERNS` in `init.conf`
- Ensure repositories have a `.git` directory

### Could not determine git username

**Problem**: "Error: Could not determine git username"

**Solutions**:
- Configure git: `git config --global user.name "Your Name"`
- Or provide username: `./run.sh --username yourname`
- Or set `DEFAULT_USERNAME` in `init.conf`

### No commits found

**Problem**: Repositories are found but no commits in output

**Possible causes**:
- Date range doesn't include any commits
- Username doesn't match commit author
- Repository has no commits in the specified branch

**Solutions**:
- Verify date range with `git log --author="username" --since="date"`
- Check exact author name in commits: `git log --format="%an" | sort -u`
- Try a wider date range

### Permission denied

**Problem**: "Permission denied" when running script

**Solution**:
```bash
chmod +x run.sh
```

### Script fails on Windows

**Problem**: Script doesn't work on Windows

**Solutions**:
- Use Git Bash (comes with Git for Windows)
- Use WSL (Windows Subsystem for Linux)
- Ensure line endings are Unix-style (LF not CRLF)

### Slow performance

**Problem**: Script takes too long to complete

**Solutions**:
- Increase `MAX_PARALLEL_JOBS` in `init.conf`
- Reduce the number of repositories with `REPO_INCLUDE_PATTERNS`
- Use more specific date ranges

## Advanced Usage

### Custom Git Log Options

Add additional git log flags via `GIT_LOG_OPTIONS` in `init.conf`:

```bash
# Example: Only show commits on first-parent
GIT_LOG_OPTIONS="--first-parent"
```

### Filtering Repositories

Use pattern matching to scan only specific repositories:

**init.conf:**
```bash
REPO_INCLUDE_PATTERNS="project-* app-*"
REPO_EXCLUDE_PATTERNS="*-archived *-test"
```

### Automation

Run the script as a cron job or scheduled task:

```bash
# Daily report for yesterday
./run.sh --qNumber 0 --username $(git config user.name) > /tmp/git-report.log 2>&1
```

## Version

Current version: 1.0.0

## License

This script is provided as-is without warranty. Feel free to read the [LICENSE](./LICENSE) file for details.

© 2026 ixicale. All rights reserved.
