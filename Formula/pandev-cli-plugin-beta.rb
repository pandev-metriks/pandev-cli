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
#   2.5.15           semantic version, e.g. 2.5.0
#   v2.5.15-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   c1c1341dfe6e4dcdc2b034b0d4e33e5b460eed15ad191bc4fb882ff50068d951 / 6cd8561246b1569fe0cd0be84a0ff294bad9f9d3039b2b690a236f6d37264757 / 8e912d9560ddceacbb1fb594e78d6c06d03866b55832190e18aec18f9e243eb4  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.15"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.15-beta/pandev-cli-plugin_2.5.15_macOS_amd64.tar.gz"
      sha256 "c1c1341dfe6e4dcdc2b034b0d4e33e5b460eed15ad191bc4fb882ff50068d951"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.15-beta/pandev-cli-plugin_2.5.15_macOS_arm64.tar.gz"
      sha256 "6cd8561246b1569fe0cd0be84a0ff294bad9f9d3039b2b690a236f6d37264757"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.15-beta/pandev-cli-plugin_2.5.15_Linux_amd64.tar.gz"
    sha256 "8e912d9560ddceacbb1fb594e78d6c06d03866b55832190e18aec18f9e243eb4"
  end

  conflicts_with "pandev-cli-plugin", because: "both install the `pandev` and `pandev-cli-plugin` binaries"

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
