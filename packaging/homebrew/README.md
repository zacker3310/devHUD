# Homebrew distribution

The cask in `Casks/devhud.rb` belongs in a tap repository named
`zacker3310/homebrew-tap` (Homebrew requires the `homebrew-` prefix). Copy the
file there on every release; `scripts/release.sh` rewrites `version` and
`sha256` in this copy.

Install, with admin rights:

    brew tap zacker3310/tap
    brew install --cask devhud

Install without admin rights (managed MacBooks). Homebrew itself can live in the
home directory (the "untar anywhere" install), and the cask goes to
`~/Applications`:

    export HOMEBREW_CASK_OPTS="--appdir=~/Applications"
    brew install --cask zacker3310/tap/devhud

Requirements for the cask to work for anyone but the author:

- The GitHub repository (or at least its releases) must be public. Homebrew
  downloads anonymously.
- The zip must be Developer ID signed and notarized. Homebrew keeps the
  quarantine flag; an ad-hoc build is blocked by Gatekeeper on macOS 15 and
  later with no right-click bypass.
