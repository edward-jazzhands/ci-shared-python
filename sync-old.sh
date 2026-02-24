#!/usr/bin/env bash
set -euo pipefail

REPO="edward-jazzhands/ci-shared-python"
BRANCH="main"
API_BASE="https://api.github.com/repos/${REPO}/contents/.github?ref=${BRANCH}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/.github"

# This script requires jq to be installed. It's commonly included in many distros.
# This checks if we can print the command path to /dev/null, which is a typical way
# to check if a program is installed on Unix-like systems.
if ! command -v jq &>/dev/null; then
	echo "Error: jq is required but not installed. Install it with 'apt install jq' or 'brew install jq'." >&2
	exit 1
fi

# To install jq on Debian/Ubuntu, run:
# sudo apt install jq

fetch_contents() {
	local api_url="$1"
	local local_dir="$2"

	mkdir -p "$local_dir"

	# We declare 'entries' as local first, then assign it on the next line.
	# This is necessary — if you write `local entries=$(...)` in one line,
	# bash sets the exit code of the 'local' builtin rather than the command
	# substitution, which would silently swallow errors even with 'set -e'.
	# Splitting it onto two lines means the assignment's exit code is checked.
	local entries

	# $(...) runs curl and captures its stdout as a string.
	# On the first run of this function, this will be the API_BASE URL above
	# and it will return JSON data about the contents of the .github directory.
	entries=$(curl -fsSL "$api_url")

	# The while loop below doesn't reference $entries anywhere in its opening line, 
	# so it looks like it's reading from thin air. The connection is on the `done` line
	# at the end of the while loop.

	# IFS= prevents the shell from splitting on whitespace within each line.
	# By default IFS contains space, tab, and newline — setting it to empty here
	# means 'read' won't trim leading/trailing whitespace from each line.
	# -r tells read to treat backslashes literally rather than as escape chars.
	# 'entry' is the variable that receives each line of input on each iteration.

	# `read` returns exit code 0 when it successfully reads a line, and non-zero when 
	# there's nothing left. `while` keeps looping as long as the condition is true 
	# (exit code 0), and stops when it's false. So the loop is self-terminating based on 
	# whether there's any data left in stdin
	while IFS= read -r entry; do

		# Again, declare locals before assigning to avoid swallowing exit codes.
		# All three are scoped to this function (and this iteration, effectively).
		local type name path

		# jq -r means "raw output" — without it, string values would be wrapped
		# in quotes in the output. The argument is a jq filter: .type, .name, and
		# .path are property accessors on the current JSON object. Since we're
		# feeding one JSON object per iteration (see the done < <(...) below),
		# each of these just plucks the named field's value as a plain string.
		type=$(echo "$entry" | jq -r '.type')
		name=$(echo "$entry" | jq -r '.name')
		path=$(echo "$entry" | jq -r '.path')

		# [[ ]] is bash's extended conditional syntax (safer than [ ] for string
		# comparisons — no word splitting or glob expansion happens inside it).
		if [[ "$type" == "file" ]]; then
			local file_path="${local_dir}/${name}"
			echo "Copying: $file_path"

			# ${path#.github/} is a parameter expansion that strips the prefix
			# ".github/" from the value of $path. The # operator removes the
			# shortest matching prefix pattern. So ".github/workflows/ci.yml"
			# becomes "workflows/ci.yml", which we append to $RAW_BASE to form
			# the correct raw file URL.
			# -o tells curl to write the output to a file instead of stdout.
			curl -fsSL "${RAW_BASE}/${path#.github/}" -o "$file_path"

		elif [[ "$type" == "dir" ]]; then
			# ${API_BASE%\?*} is a parameter expansion using % which strips the
			# shortest matching suffix pattern. \?* means a literal "?" followed by
			# anything — so it strips the query string off $API_BASE, leaving just
			# the base URL path. We then append the subdirectory path and re-add
			# the ?ref= query param to form a valid API URL for the subdirectory.
			# We then call fetch_contents recursively with this new URL and the
			# corresponding local subdirectory path — this is how the whole tree
			# gets walked without us knowing the structure ahead of time.
			fetch_contents "${API_BASE%\?*}/${path}?ref=${BRANCH}" "${local_dir}/${name}"
		fi

	# See extended explanation below.
	done < <(echo "$entries" | jq -c '.[]')
}


TARGET_DIR="$(pwd)/.github"
echo "Syncing .github/ into ${TARGET_DIR}"
fetch_contents "$API_BASE" "$TARGET_DIR"
echo "Done."

# == ABOUT THE WHILE LOOP ==

# `done < <(...)`` is a process substitution feeding into the while loop using
# reverse redirection. Reverse redirection in bash is a bit confusing since the 
# data we want to feed into the loop has to be written at the end of the loop
# (which is represented by the `done` keyword).

# `<(...)`` runs the inner command in a subshell and presents its output as
#   if it were a file (So it can be read by programs such as 'cat').
# The leftmost < is a reverse redirect that feeds into the while loop's stdin.
#   Note the direction of the redirect symbol is reversed from the normal `>`.

# This is different from piping (... | while) because piping runs the while loop in 
# a subshell, meaning any variables set inside it would be lost after the loop ends. 
# Process substitution keeps the while loop in the current shell. This is necessary
# for a script like this because we need to read from the API in a loop, and piping
# would not preserve the variables set earlier in the script.

# jq -c '.[]' iterates over the top-level JSON array that the GitHub API
# returns and outputs each element as a compact (-c) single-line JSON object.
# That gives us one JSON object per line, which the while loop reads one at
# a time into $entry.

# So to summarize:
#   - Inside a subshell, echo the $entries var, which returns JSON from the Github API.
#   - This is piped into jq, which converts the JSON into a single line per object.
#   - The entire jq output is converted into a virtual file by the subshell.
# Now that we have the virtual file, we feed it into the while loop:
#   done < [virtual-file]

# In case its not clear enough how the loop works, consider this example:

# while IFS= read -r entry; do
#   echo "$entry"
# done < some_file.txt

# Note the reverse order of the redirection symbol. A normal forward redirection
# looks like this:
# some_command > some_file.txt

# The while loop above is reading from some_file.txt, and converting each line of 
# input into an $entry variable. This is indeed a bit backwards from how most
# other languages handle this situation. But bash is a special language.
