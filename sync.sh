#!/usr/bin/env bash
set -euo pipefail

REPO="edward-jazzhands/ci-shared-python"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ASCII Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


# To install jq on Debian/Ubuntu, run:
# sudo apt install jq

# This script requires jq to be installed. It's commonly included in many distros.
# This checks if we can print the command path to /dev/null, which is a typical way
# to check if a program is installed on Unix-like systems.
if ! command -v jq &>/dev/null; then
	printf "Error: jq is required but not installed. Install it with 'apt install jq' or 'brew install jq'.\n" >&2
	exit 1
fi

# Step 1: Resolve branch to commit SHA
# $(...) runs the contents and captures its stdout as a string.
# We first curl the script, which will store it in memory as a string, then 
# pipe that string into jq to parse the JSON.
# The -r flag means 'raw output'. It tells jq to output the value of the `.sha` field,
# meaning without the surrounding quotes.
COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/${REPO}/commits/${BRANCH}" | jq -r '.sha')

# Step 2: Fetch the full recursive tree in one call
# Now that we have the commit SHA for the branch, we can fetch the full tree
# for that commit. Github has a `?recursive=1` query param to fetch the entire tree.
# This is preferable for us because we only need one API call.
TREE=$(curl -fsSL "https://api.github.com/repos/${REPO}/git/trees/${COMMIT_SHA}?recursive=1")

TARGET_DIR="$(pwd)/.github"
printf "Syncing into ${GREEN}${TARGET_DIR}${NC}\n"


# `while IFS= read -r file_path` reads one line at a time from the input.
# (which is from the reverse redirection at the end of the while loop)
# IFS= (setting the internal field separator to empty) prevents bash from trimming
# leading/trailing whitespace from each line.

# -r tells read to treat backslashes literally rather than as escape chars.
# 'file_path' is the variable that each line of input is assigned to.

# `read` returns exit code 0 when it successfully reads a line, and non-zero when 
# there's nothing left. `while` keeps looping as long as the condition is true 
# (exit code 0), and stops when it's false. So the loop is self-terminating based on 
# whether there's any data left in stdin
while IFS= read -r file_path; do

	# file_path is something like .github/workflows/ci.yml
	# We want the local path to be .github/workflows/ci.yml inside TARGET_DIR,
	# but without duplicating the .github/ prefix.
	# ${file_path#.github/} is bash parameter expansion — the # strips the shortest
	# match of the pattern ".github/" from the front of the variable's value.
	# So .github/workflows/ci.yml becomes workflows/ci.yml, and we prepend TARGET_DIR
	# to get the full local destination path.
	local_path="${TARGET_DIR}/${file_path#.github/}"

	# dirname strips the filename from the path, leaving just the directory portion.
	# e.g. /some/dir/.github/workflows/ci.yml → /some/dir/.github/workflows
	mkdir -p "$(dirname "$local_path")"

	if [ -f "$local_path" ]; then
		printf "${CYAN}Overwriting${NC} existing file: $local_path \n"
	else
		printf "${YELLOW}Adding${NC} new file: $local_path \n"
	fi

	# Construct the raw download URL by joining RAW_BASE with the full file_path
	# (e.g. https://raw.githubusercontent.com/org/repo/main/.github/workflows/ci.yml)
	# -o writes the response body to local_path instead of stdout.
	curl -fsSL "${RAW_BASE}/${file_path}" -o "$local_path"

# Inside jq, `.tree[]` unpacks the array of tree entries into individual objects.
# `select(...)` filters those objects, keeping only entries where:
#   - .type == "blob"  → blob is git's term for a file (as opposed to "tree" which is a dir)
#   - .path | startswith(".github/")  → the pipe here is jq's pipe, passing .path into
#     the startswith() function to make sure we only grab files inside .github/
#
# The final `| .path` extracts just the path string from each matched object.
done < <(echo "$TREE" | jq -r '.tree[] | select(.type == "blob" and (.path | startswith(".github/"))) | .path')
#    │
#    ├ this thing here
#    └ This is the while loop's stdin. Note the direction of the redirect symbol.

printf "Done.\n"

# == ABOUT `done <` AND THE WHILE LOOP ==

# `done < <(...)`` is a process substitution feeding into the while loop using
# reverse redirection. Reverse redirection in bash is a bit confusing since the 
# data we want to feed into the loop has to be written at the end of the loop
# (which is represented by the `done` keyword).

# `<(...)`` runs the inner command in a subshell and presents its output as
#   if it were a file (So it can be read by programs such as 'cat').
# The leftmost < is a reverse redirect that feeds into the while loop's stdin.
#   Note the direction of the redirect symbol is reversed from the normal `>`.

# In case its not clear enough how the loop works, consider this example:

# while IFS= read -r entry; do
#   echo "$entry"
# done < some_file.txt

# Note the reverse order of the redirection symbol. A normal forward 
# redirection looks like this:

# some_command > some_file.txt

# The while loop above is reading from some_file.txt, and converting each line of 
# input into an $entry variable. This looks a bit backwards from how most
# other languages handle this situation. But bash is a special language.

