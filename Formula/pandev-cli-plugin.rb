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
#   2.5.22           semantic version, e.g. 2.5.0
#   v2.5.22               release tag hosting the assets, e.g. v2.5.0
#   44e7e4fc4339862642100fd4fbb5b002c30617930a559c8bda095953be52dc30 / 2a261bbbd429c913ad3af43a530847bf2069e6bd1e0c81c9259724fd8c5371d7 / fad255cb44ca803f48c7b17b74632d0c41f9ba4c596eceab453a1b15dcbb9d4b  asset checksums
class PandevCliPlugin < Formula
  desc "PanDev Metrics CLI"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.22"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22/pandev-cli-plugin_2.5.22_macOS_amd64.tar.gz"
      sha256 "44e7e4fc4339862642100fd4fbb5b002c30617930a559c8bda095953be52dc30"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22/pandev-cli-plugin_2.5.22_macOS_arm64.tar.gz"
      sha256 "2a261bbbd429c913ad3af43a530847bf2069e6bd1e0c81c9259724fd8c5371d7"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.22/pandev-cli-plugin_2.5.22_Linux_amd64.tar.gz"
    sha256 "fad255cb44ca803f48c7b17b74632d0c41f9ba4c596eceab453a1b15dcbb9d4b"
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
