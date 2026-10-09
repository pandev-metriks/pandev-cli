# Formula template: pandev-cli-plugin (stable channel).
#
# Source of truth lives in the CLI repo at release/formula/pandev-cli-plugin.rb.
# The Production Release workflow renders it (replacing the @-tokens below) and
# commits the result to Formula/pandev-cli-plugin.rb in pandev-metriks/pandev-cli,
# and — during the transition period — verbatim to the legacy tap
# pandev-metriks/homebrew-pandev-cli so existing brew clients keep updating.
# Never edit the rendered copies by hand: the next release overwrites them.
#
# Tokens replaced by CI (do NOT pre-fill):
#   2.5.21           semantic version, e.g. 2.5.0
#   v2.5.21               release tag hosting the assets, e.g. v2.5.0
#   d80653c7345ed13c7fc702b56234de07411841f881a3265ee3739c4f01178016 / 490599bdc8a7e9946c4fdf6e12f7dbd0291a0f57e7a545dc749db075d75a6ead / 3688a4a6961c039b937985229e446d033836a809fba522c6a1b07b73eb27cd7a  asset checksums
class PandevCliPlugin < Formula
  desc "PanDev Metrics CLI"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.21"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21/pandev-cli-plugin_2.5.21_macOS_amd64.tar.gz"
      sha256 "d80653c7345ed13c7fc702b56234de07411841f881a3265ee3739c4f01178016"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21/pandev-cli-plugin_2.5.21_macOS_arm64.tar.gz"
      sha256 "490599bdc8a7e9946c4fdf6e12f7dbd0291a0f57e7a545dc749db075d75a6ead"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21/pandev-cli-plugin_2.5.21_Linux_amd64.tar.gz"
    sha256 "3688a4a6961c039b937985229e446d033836a809fba522c6a1b07b73eb27cd7a"
  end

  # No `conflicts_with "pandev-cli-plugin-beta"`: to check it, brew loads the beta formula,
  # and since Homebrew 6.0 it refuses to load a formula from an untrusted tap — installing
  # the stable one by its full name failed on that refusal (PDM-4862). The installer removes
  # the other channel before installing, and brew's own link step still refuses to overwrite
  # the other formula's `pandev`.

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
