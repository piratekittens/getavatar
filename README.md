# Get Avatar server

A web page on your own Mac that shows every Claude Code agent you run, live: what each one is
doing, which ones are waiting for you, and what they cost. On a new install everything that acts
on its own is switched off until you turn it on.

This repository holds only the installer. The server itself is in the private repository
`piratekittens/avatar-server`: you need to have been given access to it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/piratekittens/getavatar/main/install.sh | sh
```

What it does, each step printed:

1. Checks that this is a Mac, and that `git` and Claude Code (`claude`) are installed.
2. Installs `mise` with mise's own installer when it is missing (it installs the Erlang and
   Elixir the server needs).
3. Clones `piratekittens/avatar-server` into `~/code/avatar-server` (set `AVATAR_SERVER_DIR` for
   another folder). A checkout already there is left as it is.
4. Runs that checkout's `bin/install`, which builds the server and writes its first settings.
5. Prints the address, `http://127.0.0.1:4747`, how to update and where the docs are.

What it will ask: the questions of `bin/install`, each answered by you, default no (the Stop
hook and the status line in Claude Code's settings, the Tidewave line). It says yes for you to
two: downloading and running Herdr's installer when `hc` or the Herdr app is missing (the page
shows only agents run by `hc`), and starting the server at login. To be asked those too, run
`bin/install` yourself instead (below).

## What you need first

- A Mac.
- `git`: `xcode-select --install` gives it.
- Claude Code. When it is missing the installer stops and prints Claude Code's own install
  line (`curl -fsSL https://claude.ai/install.sh | bash`, from
  https://code.claude.com/docs/en/setup). Run the line above again after.
- Access to `piratekittens/avatar-server`, and `git` signed in to GitHub (next section).

## Signing in to the private repository

**1. Accept the invitation.** Signed in to github.com as the account that was invited, open
the invitation email, or https://github.com/piratekittens/avatar-server/invitations, and accept
it.

**2. Sign `git` in to GitHub.** The simple way is GitHub's own `gh` program, over HTTPS:

1. Install it: `brew install gh` (or from https://cli.github.com).
2. Run `gh auth login`.
3. Choose `GitHub.com`, then `HTTPS`.
4. Answer yes to "Authenticate Git with your GitHub credentials?".
5. Choose "Login with a web browser", copy the code it shows, and confirm in the browser.

Or with an SSH key:

```sh
ssh-keygen -t ed25519            # Enter for the defaults
pbcopy < ~/.ssh/id_ed25519.pub   # then paste it at https://github.com/settings/keys
ssh -T git@github.com            # says "Hi <your name>!" when it works
```

**3. Check.** This prints a line (a commit and `HEAD`) when both are in place:

```sh
git ls-remote https://github.com/piratekittens/avatar-server.git
```

With SSH: `git ls-remote git@github.com:piratekittens/avatar-server.git`.

When the installer cannot clone, it says which of the two is missing as far as it can tell:
no sign-in that `git` could use, or a sign-in whose account cannot see the repository (the
invitation not accepted yet, or another account signed in).

## Read it before you run it

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/piratekittens/getavatar/main/install.sh
less install.sh
sh install.sh
```

## A dry run

Options after `sh -s --` go to `bin/install`. `--dry-run` changes nothing:

```sh
curl -fsSL https://raw.githubusercontent.com/piratekittens/getavatar/main/install.sh | sh -s -- --dry-run
```

With no checkout yet it says what it would install and clone, and stops before cloning. With
a checkout it runs `bin/install --dry-run` there, which prints every step it would take.

## Updating

```sh
cd ~/code/avatar-server && bin/update
```

The page also says when an update is there.

## By hand

```sh
git clone https://github.com/piratekittens/avatar-server.git ~/code/avatar-server
cd ~/code/avatar-server
bin/install --dry-run
bin/install
```

## Removing it

See "Removing everything" in `docs/install.md` of the private repository (in your checkout:
`~/code/avatar-server/docs/install.md`).

## What this installer never does

- It never uses `sudo`. It writes in your home folder, in a temporary folder it removes at
  the end, and what mise's and Herdr's own installers write.
- It never installs Claude Code.
- It never changes a checkout that is already there: updating is `bin/update`'s.
- It never waits on a hidden password prompt: a missing sign-in fails at once, and each clone
  has a time limit.
- A download cut short runs nothing: the whole script is one function called on its last line.
