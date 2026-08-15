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
#   2.4.13           semantic version, e.g. 2.5.0
#   v2.4.13               release tag hosting the assets, e.g. v2.5.0
#   b8c3675b97117339889220b4c82bbbe813e5d150e6daf186c78e3331ceb9fc22 / cc133dd29d99c767dcef73c2d57949fb47c7d75819a0a1f069b403e9bd31799f / 783038f1a6bc63aec096d1f7689c17a141194c504de3251677f04dee744084f3  asset checksums
class PandevCliPlugin < Formula
  desc "PanDev Metrics CLI"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.13"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13/pandev-cli-plugin_2.4.13_macOS_amd64.tar.gz"
      sha256 "b8c3675b97117339889220b4c82bbbe813e5d150e6daf186c78e3331ceb9fc22"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13/pandev-cli-plugin_2.4.13_macOS_arm64.tar.gz"
      sha256 "cc133dd29d99c767dcef73c2d57949fb47c7d75819a0a1f069b403e9bd31799f"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13/pandev-cli-plugin_2.4.13_Linux_amd64.tar.gz"
    sha256 "783038f1a6bc63aec096d1f7689c17a141194c504de3251677f04dee744084f3"
  end

  conflicts_with "pandev-cli-plugin-beta", because: "both install the `pandev` and `pandev-cli-plugin` binaries"

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
