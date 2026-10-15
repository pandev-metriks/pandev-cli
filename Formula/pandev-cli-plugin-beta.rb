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
#   2.5.22           semantic version, e.g. 2.5.0
#   v2.5.22-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   e94b8ca77306c44b96542b361bdd1778af7339adb9e96462ff73f1b13cee2a00 / 68024a6be2fe0f93b6217fedb96f9c1d79b6baaf546653794e67b68283daf63d / 8f20975940dd0586646541297ffd0384776c98856cd62f11cf1ce13e7cbb6444  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.22"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22-beta/pandev-cli-plugin_2.5.22_macOS_amd64.tar.gz"
      sha256 "e94b8ca77306c44b96542b361bdd1778af7339adb9e96462ff73f1b13cee2a00"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22-beta/pandev-cli-plugin_2.5.22_macOS_arm64.tar.gz"
      sha256 "68024a6be2fe0f93b6217fedb96f9c1d79b6baaf546653794e67b68283daf63d"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22-beta/pandev-cli-plugin_2.5.22_Linux_amd64.tar.gz"
    sha256 "8f20975940dd0586646541297ffd0384776c98856cd62f11cf1ce13e7cbb6444"
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
