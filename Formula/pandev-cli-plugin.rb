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
#   2.5.16           semantic version, e.g. 2.5.0
#   v2.5.16               release tag hosting the assets, e.g. v2.5.0
#   0ac911bf18a978fc9774c9759a26772339692364f5ab5ebe83c2cf4129b9c776 / bd5c85f1456ec40f98dd7c82fbd69fefd17f268123ac527610fa705ed897c18d / c43b4cb9f04717f82a7c45510374e363f73b01b8a52a4a61ea23546359c25ffd  asset checksums
class PandevCliPlugin < Formula
  desc "PanDev Metrics CLI"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.16"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.16/pandev-cli-plugin_2.5.16_macOS_amd64.tar.gz"
      sha256 "0ac911bf18a978fc9774c9759a26772339692364f5ab5ebe83c2cf4129b9c776"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.16/pandev-cli-plugin_2.5.16_macOS_arm64.tar.gz"
      sha256 "bd5c85f1456ec40f98dd7c82fbd69fefd17f268123ac527610fa705ed897c18d"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.16/pandev-cli-plugin_2.5.16_Linux_amd64.tar.gz"
    sha256 "c43b4cb9f04717f82a7c45510374e363f73b01b8a52a4a61ea23546359c25ffd"
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
