#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
USAGE:
    expand-bump-prs.sh [OPTIONS] [FILE]

Expand release-note bullets containing bump PR links with the descriptions
from those PRs. Read FILE, or standard input when FILE is omitted or '-'.
Output goes to standard output unless --in-place is used.

OPTIONS:
    -i, --in-place    replace FILE in place (requires FILE)
    -q, --quiet       suppress progress messages
    -h, --help        show this help
EOF
}

in_place=''
quiet=''
file='-'
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        -i | --in-place)
            in_place=1
            ;;
        -q | --quiet)
            quiet=1
            ;;
        --)
            shift
            [[ $# -le 1 ]] || { echo "ERROR: expected at most one FILE" >&2; exit 2; }
            [[ $# -eq 1 ]] && file=$1
            break
            ;;
        -* )
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            [[ "$file" = '-' ]] || { echo "ERROR: expected at most one FILE" >&2; exit 2; }
            file=$1
            ;;
    esac
    shift
done

if [[ -n "$in_place" && "$file" = '-' ]]; then
    echo "ERROR: --in-place requires FILE" >&2
    exit 2
fi

if ! command -v gh >/dev/null; then
    echo "ERROR: gh command not found" >&2
    exit 2
fi

input=$(mktemp)
output=$(mktemp)
trap 'rm -f "$input" "$output"' EXIT
if [[ "$file" = '-' ]]; then
    cat >"$input"
else
    cp -- "$file" "$input"
fi

declare -A body_cache
fetched_body=''
matched=0
expanded=0

log() {
    [[ -n "$quiet" ]] || printf '%s\n' "$*" >&2
}

fetch_body() {
    local repo=$1
    local number=$2
    local key="$repo#$number"

    if [[ ${body_cache[$key]+yes} ]]; then
        fetched_body="${body_cache[$key]}"
        return
    fi

    local body
    log "Fetching $key..."
    if ! body=$(gh pr view "$number" --repo "$repo" --json body --template '{{.body}}'); then
        echo "WARNING: unable to read $repo#$number; leaving bullet unchanged" >&2
        fetched_body='__GH_ERROR__'
        body_cache[$key]=$fetched_body
        return
    fi

    # Reviewable adds a large, non-release-note footer to older PRs.
    body=$(printf '%s\n' "$body" | awk '/<!--[[:space:]]*Reviewable:start[[:space:]]*-->/{exit} {print}')
    fetched_body=$body
    body_cache[$key]=$fetched_body
}

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*\*.*[Bb]ump.*https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
        repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        number="${BASH_REMATCH[3]}"
        ((matched += 1))
        fetch_body "$repo" "$number"
        body=$fetched_body
        if [[ "$body" != '__GH_ERROR__' && -n "${body//[[:space:]]/}" ]]; then
            log "Expanding $repo#$number."
            ((expanded += 1))
            printf '%s\n' "$line" >>"$output"
            while IFS= read -r body_line || [[ -n "$body_line" ]]; do
                printf '  %s\n' "$body_line" >>"$output"
            done <<<"$body"
            continue
        fi
        [[ "$body" = '__GH_ERROR__' ]] || log "Skipping $repo#$number: no description."
    fi
    printf '%s\n' "$line" >>"$output"
done <"$input"

log "Done: expanded $expanded of $matched matching PRs."

if [[ -n "$in_place" ]]; then
    cp -- "$output" "$file"
else
    cat "$output"
fi
