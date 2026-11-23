#!/bin/sh
# install.sh: install Avatar server on this Mac with one line.
#
#   curl -fsSL https://raw.githubusercontent.com/piratekittens/getavatar/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/piratekittens/getavatar/main/install.sh | sh -s -- --dry-run
#
# 1. Checks for macOS, git and Claude Code (when Claude Code is missing it stops and prints
#    Claude Code's own install line).
# 2. Installs mise with mise's own installer when it is missing.
# 3. Clones the private repository piratekittens/avatar-server into ~/code/avatar-server
#    (AVATAR_SERVER_DIR for another folder): HTTPS, then gh, then SSH. A checkout already there is left as it is.
# 4. Runs that checkout's bin/install, with yes to Herdr (when hc is missing) and to start at login.
# 5. Prints the address, how to update and where the docs are.
# 6. Never uses sudo; writes in your home folder, a temporary folder it removes, and what mise's
#    and Herdr's own installers write.
#
# Options after `sh -s --` go to bin/install (--dry-run changes nothing here either).
# The copy in piratekittens/getavatar is kept in the avatar-server repository and copied here as
# it is. Everything is in one function called on the last line: a download cut short runs nothing.

REPO_SLUG=piratekittens/avatar-server
REPO_HTTPS=https://github.com/$REPO_SLUG.git
REPO_SSH=git@github.com:$REPO_SLUG.git
INVITATIONS=https://github.com/$REPO_SLUG/invitations
MISE_URL=https://mise.run
CLAUDE_LINE='curl -fsSL https://claude.ai/install.sh | bash'
CLAUDE_DOCS=https://code.claude.com/docs/en/setup
ADDRESS=http://127.0.0.1:4747

say() { printf '%s\n' "$*"; }
would() { say "  would: $*"; }
stop() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

# a terminal to ask in: stdout is one and /dev/tty opens (stdin is the pipe from curl)
has_terminal() { [ -t 1 ] && (exec </dev/tty) 2>/dev/null; }

# bounded SECONDS CMD...: CMD with its output in $ERR, stopped after SECONDS (status 124); a
# watcher beside it ends it at the limit and is ended itself when CMD ends first. Only CMD's
# own process is ended: a program it started (the git under gh) may go on writing for a while
# after the limit, also while a failed try's folder is removed and the next try runs.
bounded() {
  limit=$1
  shift
  "$@" </dev/null >>"$ERR" 2>&1 &
  pid=$!
  (
    n=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$n" -ge "$limit" ]; then
        : >"$WORK/timed"
        kill "$pid"
        break
      fi
      sleep 1
      n=$((n + 1))
    done
  ) >/dev/null 2>&1 &
  watcher=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$watcher" 2>/dev/null
  # waited for, so that the shell prints no "Terminated" line for it
  wait "$watcher" 2>/dev/null
  if [ -e "$WORK/timed" ]; then
    rm -f "$WORK/timed"
    rc=124
  fi
  return $rc
}

# mise on PATH, or in ~/.local/bin (where its installer puts it), then on PATH for this run
find_mise() {
  command -v mise >/dev/null 2>&1 && return 0
  [ -x "$HOME/.local/bin/mise" ] || return 1
  PATH="$HOME/.local/bin:$PATH"
  export PATH
  say "  mise is in ~/.local/bin, which is not on this shell's PATH; this run uses it from there."
  say "  Add this line to your shell's profile (~/.zshrc) so that a new shell finds it:"
  say "    export PATH=\"\$HOME/.local/bin:\$PATH\""
}

# mise's own installer, downloaded to a temporary file and run only when it came down as a script
install_mise() {
  if [ "$DRY" = 1 ]; then
    would "curl -fsSL --proto '=https' --max-time 120 -o <a temporary file> $MISE_URL"
    would "sh <that file> (only when it starts with #!), then look for mise in ~/.local/bin"
    return 0
  fi
  tmp=$WORK/mise-install.sh
  say "  run: curl -fsSL --proto '=https' --max-time 120 -o $tmp $MISE_URL"
  curl -fsSL --proto '=https' --max-time 120 -o "$tmp" "$MISE_URL" ||
    stop "mise's installer could not be downloaded: nothing was run"
  [ -s "$tmp" ] || stop "mise's installer came down empty: nothing was run"
  IFS= read -r first <"$tmp" || first=""
  case $first in
    '#!'*) ;;
    *) stop "what came down is not mise's installer (no #! on its first line): nothing was run" ;;
  esac
  say "  run: sh <mise's installer>"
  sh "$tmp" </dev/null || stop "mise's installer failed (its lines are above)"
  rm -f "$tmp"
  find_mise || stop "mise's installer ran, but mise is not found (not on PATH, not in ~/.local/bin)"
  say "  mise: installed"
}

# the folder is a git checkout of avatar-server, at its top, with bin/install
our_checkout() {
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd "$top" && pwd -P)" = "$(cd "$1" && pwd -P)" ] || return 1
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  case $url in
    *[:/]$REPO_SLUG | *[:/]$REPO_SLUG.git) [ -x "$1/bin/install" ] ;;
    *) return 1 ;;
  esac
}

# try_clone WHAT CMD...: one way to clone, bounded; what a failed try left is removed
try_clone() {
  what=$1
  shift
  say "  trying $what"
  : >"$ERR"
  bounded "$CLONE_LIMIT" "$@"
  rc=$?
  [ $rc = 0 ] && [ -x "$DIR/bin/install" ] && return 0
  [ $rc = 124 ] && say "    stopped after $CLONE_LIMIT seconds without an end"
  grep -v '^[[:space:]]*$' "$ERR" | tail -n 2 | sed 's/^/    /'
  cat "$ERR" >>"$WORK/all-errors"
  if [ "$MADE" = 1 ]; then rm -rf "$DIR"; fi
  return 1
}

gh_signed_in() {
  command -v gh >/dev/null 2>&1 || return 1
  : >"$ERR"
  bounded 30 gh auth status
}

no_access() {
  say ""
  say "The clone was refused or did not finish (git's lines are above)."
  if grep -Eqi 'repository not found|could not resolve to a repository' "$WORK/all-errors"; then
    say "GitHub knew who you are, but that account cannot see the repository (yet): the likely cause."
  else
    say "The likely cause: no GitHub sign-in that git could use (a network fault or an unknown"
    say "SSH host key gives the same; git's lines say which)."
  fi
  say "The repository $REPO_SLUG is private. To clone it you need two things:"
  say "  1. Access. You were invited: accept the invitation (the invitation email, or"
  say "     $INVITATIONS), signed in to github.com as the account that was invited."
  say "  2. git signed in to GitHub, one of two ways:"
  say "       gh auth login     (GitHub.com, HTTPS, and yes to \"Authenticate Git\")"
  say "       or an SSH key added to your GitHub account (https://github.com/settings/keys)"
  say "  Check: git ls-remote $REPO_HTTPS"
  say "     or: git ls-remote $REPO_SSH  (with SSH)"
  say "  prints a line when both are in place."
  say "Then run this line again."
  exit 1
}

main() {
  set -u
  : "${HOME:?HOME is not set}"
  DRY=0
  for arg in "$@"; do
    case $arg in --dry-run) DRY=1 ;; esac
  done
  DIR=${AVATAR_SERVER_DIR:-$HOME/code/avatar-server}
  case $DIR in /*) ;; *) DIR=$PWD/$DIR ;; esac
  CLONE_LIMIT=${AVATAR_CLONE_LIMIT:-900}
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/getavatar.XXXXXX") || stop "no temporary folder could be made"
  ERR=$WORK/err
  trap 'rm -rf "$WORK"' EXIT
  trap 'rm -rf "$WORK"; exit 1' INT TERM

  say "Avatar server: install$([ "$DRY" = 1 ] && printf ' (dry run: nothing is changed)')"

  say "1. This Mac, git, Claude Code"
  [ "$(uname -s)" = Darwin ] || stop "this installer is for macOS only"
  git --version >/dev/null 2>&1 ||
    stop "git is missing: run  xcode-select --install  (the Xcode command line tools), then run this line again"
  if ! command -v claude >/dev/null 2>&1; then
    say "  Claude Code (claude) is not installed. The server watches Claude Code sessions."
    say "  Install it with its own installer ($CLAUDE_DOCS):"
    say "    $CLAUDE_LINE"
    say "  then open a new terminal and run this line again."
    exit 1
  fi
  say "  macOS, git, claude: found"

  say "2. mise (it installs the Erlang and Elixir the server is pinned to)"
  if find_mise; then
    say "  mise: found"
  else
    say "  mise is not installed: installing it with its own installer from $MISE_URL"
    install_mise
  fi

  say "3. The checkout: $DIR"
  MADE=0
  if [ -e "$DIR" ] && ! { [ -d "$DIR" ] && [ -z "$(ls -A "$DIR")" ]; }; then
    our_checkout "$DIR" ||
      stop "$DIR is there and is not a checkout of $REPO_SLUG: nothing was changed (move it, or set AVATAR_SERVER_DIR to another folder)"
    say "  already a checkout of avatar-server: left as it is (bin/update updates it)"
  elif [ "$DRY" = 1 ]; then
    would "git clone $REPO_HTTPS $DIR (then gh repo clone, then $REPO_SSH)"
    say ""
    say "Dry run: there is no checkout yet to run bin/install --dry-run in; stopping here. Nothing was changed."
    exit 0
  else
    [ -e "$DIR" ] || MADE=1
    mkdir -p "$(dirname "$DIR")" || stop "the folder for the checkout could not be made"
    GIT_TERMINAL_PROMPT=0
    export GIT_TERMINAL_PROMPT
    if try_clone "HTTPS: $REPO_HTTPS" git clone --quiet -- "$REPO_HTTPS" "$DIR"; then
      :
    elif gh_signed_in && try_clone "gh (signed in): gh repo clone $REPO_SLUG" \
      gh repo clone "$REPO_SLUG" "$DIR" -- --quiet; then
      :
    elif try_clone "SSH: $REPO_SSH" env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=20" \
      git clone --quiet -- "$REPO_SSH" "$DIR"; then
      :
    else
      no_access
    fi
    say "  cloned"
  fi

  say "4. bin/install (yes to Herdr when hc is missing, and to start at login)"
  if has_terminal; then
    say "  run: $DIR/bin/install --yes-to herdr,launchd $*"
    "$DIR/bin/install" --yes-to herdr,launchd "$@" </dev/tty
  else
    say "  no terminal to ask in: run: $DIR/bin/install --no-input --yes-to herdr,launchd $*"
    "$DIR/bin/install" --no-input --yes-to herdr,launchd "$@" </dev/null
  fi
  rc=$?
  [ $rc = 0 ] ||
    stop "bin/install stopped (its lines are above): do what it says, then run this line again or $DIR/bin/install"

  say ""
  if [ "$DRY" = 1 ]; then
    say "Dry run done: nothing was changed."
    exit 0
  fi
  say "Avatar server is installed."
  say "  The page: $ADDRESS (this machine only)"
  say "  Update: cd $DIR && bin/update"
  say "  Docs: $DIR/docs/getting-started.md (and README.md, docs/install.md)"
}

{ main "$@"; }
