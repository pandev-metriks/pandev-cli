# Formula template: pandev-cli-plugin-beta (beta channel).
#
# Source of truth lives in the CLI repo at release/formula/pandev-cli-plugin-beta.rb.
# The Beta Release workflow renders it (replacing the @-tokens below) and commits
# the result to Formula/pandev-cli-plugin-beta.rb in pandev-metriks/pandev-cli.
# Never edit the rendered copy by hand: the next release overwrites it.
#
# Beta release tags look like v2.5.0-beta and are recreated in place on each
# beta of the same version — hence no immutability assumptions here.
#
# Tokens replaced by CI (do NOT pre-fill):
#   2.5.33           semantic version, e.g. 2.5.0
#   v2.5.33-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   24e4acc867fece0c5b9b900ac89ee5050e197a6e381ab81015da0284bc45e3e2 / 8cb2ebb00128a8fbca8661b424d6d17082991e640613a5bcda0babd9c937a2a4 / 4b3b39960eb8f9b593243b81193698e40ff6e767091f943460571f714e163baa  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.33"

  # No dependencies, on purpose. Homebrew upgrades every outdated dependency of a formula it
  # installs (a dependency counts as installed only at its latest version) and then their
  # outdated dependents: one PanDev update upgraded jq, git and whatever depends on them on
  # someone else's machine. Nothing here runs jq; git is the system one — Homebrew itself needs
  # it (the Command Line Tools on macOS, the distro package on Linux).

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.33-beta/pandev-cli-plugin_2.5.33_macOS_amd64.tar.gz"
      sha256 "24e4acc867fece0c5b9b900ac89ee5050e197a6e381ab81015da0284bc45e3e2"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.33-beta/pandev-cli-plugin_2.5.33_macOS_arm64.tar.gz"
      sha256 "8cb2ebb00128a8fbca8661b424d6d17082991e640613a5bcda0babd9c937a2a4"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.33-beta/pandev-cli-plugin_2.5.33_Linux_amd64.tar.gz"
    sha256 "4b3b39960eb8f9b593243b81193698e40ff6e767091f943460571f714e163baa"
  end

  # No `conflicts_with "pandev-cli-plugin"`: to check it, brew loads the stable formula, and
  # since Homebrew 6.0 it refuses to load a formula from an untrusted tap — installing the
  # beta by its full name failed on that refusal (PDM-4862). The installer removes the other
  # channel before installing, and brew's own link step still refuses to overwrite the other
  # formula's `pandev`.

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/pandev"
    bin.install_symlink libexec/"bin/pandev-cli-plugin"
  end

  def post_install
    # Create UPDATE_AVAILABLE marker to signal watcher.sh to update
    touch libexec/"UPDATE_AVAILABLE"
  end

  test do
    assert_match "version", shell_output("#{bin}/pandev status")
  end
end
