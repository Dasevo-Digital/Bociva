#!/usr/bin/env bash
# Fails when a personal identifier slips into tracked source or Git history.
set -euo pipefail

# Commits carry the maintainer's GitHub login and its noreply address, so
# GitHub attributes them to that account without a real name or mailbox.
readonly PROJECT_EMAIL='335995236+superkuh86'@'users.noreply.github.com'
readonly IDENTITY="superkuh86 <$PROJECT_EMAIL>"
readonly EXCLUDED=(
  ':(exclude)app/assets/fonts/OFL-Nunito.txt'
  ':(exclude)app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'
  ':(exclude)app/ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json'
)

fail=0
report() {
  printf '%s\n' "$1" >&2
  fail=1
}

# Findings can themselves contain the data this check is meant to protect.
# Keep only the tracked path and line number in diagnostics.
masked_locations() {
  sed -E 's/^([^:]+:[0-9]+):.*/\1: [masked]/'
}

# Synthetic fixtures: the reserved example domains (RFC 2606: example.com/
# .org/.net and the whole .example TLD, which can never be a real address),
# iCalendar UIDs and the one ntfy test URL with credentials. By domain, not by
# line number: a pinned line broke the check whenever a test above it changed.
# .invalid stays reported, the masking test relies on it.
if matches=$(git grep -n -I -i -E '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}' -- . "${EXCLUDED[@]}" \
  | grep -vi -E '@example\.(com|org|net)|@[A-Z0-9.-]+\.example([^A-Z0-9.-]|$)' \
  | grep -v -E ':[0-9]+:UID:|^server/test/family_features_test\.dart:[0-9]+: +.https://u:p@ntfy\.sh/x.,$' \
  || true); then
  if [[ -n "$matches" ]]; then
    report "Email address in a tracked file:"
    printf '%s\n' "$matches" | masked_locations >&2
  fi
fi

# Inspect the branch intended for publication. Local backup and
# remote-tracking refs are deliberately excluded because a normal branch push
# does not publish them.
if identity_commits=$(git log HEAD --format='%h%x09%aN <%aE>%x09%cN <%cE>' | while IFS=$'\t' read -r commit author committer; do
  if [[ "$author" != "$IDENTITY" || "$committer" != "$IDENTITY" ]]; then
    printf '%s\n' "$commit"
  fi
done); then
  if [[ -n "$identity_commits" ]]; then
    report "Non-project author or committer identity in reachable Git history:"
    printf '%s\n' "$identity_commits" >&2
  fi
fi

# Commit and tag messages are published as well: no addresses besides the
# project's and no co-author or generator trailers.
readonly MESSAGE_RE='[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|co-authored-by:|generated with'
for commit in $(git rev-list HEAD); do
  if hits=$(git log -1 --format=%B "$commit" | grep -i -E "$MESSAGE_RE" | grep -vF "$PROJECT_EMAIL" || true); [[ -n "$hits" ]]; then
    report "Commit ${commit:0:7}: message names a person or a tool:"
    printf '[masked]\n' >&2
  fi
done
while IFS= read -r tag; do
  if hits=$(git for-each-ref "refs/tags/$tag" --format='%(contents)' | grep -i -E "$MESSAGE_RE" | grep -vF "$PROJECT_EMAIL" || true); [[ -n "$hits" ]]; then
    report "Tag $tag: message names a person or a tool:"
    printf '[masked]\n' >&2
  fi
done < <(git tag -l)

# Typical secrets (private keys, GitHub/AWS/Slack/API tokens) in tracked
# files and anywhere in the published history.
readonly SECRET_RE='-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}'
readonly SELF=':(exclude)tool/repo_privacy_check.sh'
if matches=$(git grep -n -I -E -e "$SECRET_RE" -- . "$SELF" || true); [[ -n "$matches" ]]; then
  report "Possible secret in a tracked file:"
  printf '%s\n' "$matches" | masked_locations >&2
fi
if commits=$(git log HEAD --format='%h' --extended-regexp -G"$SECRET_RE" -- . "$SELF"); [[ -n "$commits" ]]; then
  report "Possible secret added or removed in Git history:"
  printf '%s\n' "$commits" >&2
fi

if (( fail )); then
  exit 1
fi
printf 'Repository privacy check passed.\n'
