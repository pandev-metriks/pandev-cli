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
#   2.5.34           semantic version, e.g. 2.5.0
#   v2.5.34-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   999847a72415dfb26c8de18c82126e07edde0a7fd6ca765de8de8c5066a91cce / 055e6e97e8fcc09e6809199c86c085e93010857ecf688e598929e2e9ccee88c0 / be9c45fbf436ccfa054abcd2bfad950b8db6d59f06cfd1252f369f1bad046430  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.34"

  # No dependencies, on purpose. Homebrew upgrades every outdated dependency of a formula it
  # installs (a dependency counts as installed only at its latest version) and then their
  # outdated dependents: one PanDev update upgraded jq, git and whatever depends on them on
  # someone else's machine. Nothing here runs jq; git is the system one — Homebrew itself needs
  # it (the Command Line Tools on macOS, the distro package on Linux).

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.34-beta/pandev-cli-plugin_2.5.34_macOS_amd64.tar.gz"
      sha256 "999847a72415dfb26c8de18c82126e07edde0a7fd6ca765de8de8c5066a91cce"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.34-beta/pandev-cli-plugin_2.5.34_macOS_arm64.tar.gz"
      sha256 "055e6e97e8fcc09e6809199c86c085e93010857ecf688e598929e2e9ccee88c0"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.34-beta/pandev-cli-plugin_2.5.34_Linux_amd64.tar.gz"
    sha256 "be9c45fbf436ccfa054abcd2bfad950b8db6d59f06cfd1252f369f1bad046430"
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
