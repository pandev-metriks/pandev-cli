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
#   2.4.13           semantic version, e.g. 2.5.0
#   v2.4.13-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   c7b5e52c593f24daebc9a5c77843c90486618aad3919ecdd44e6958028746d0d / af5b1d5a66fa0450534362bbcae3e7cc1363281e96bc92592d9a07d6003d3c59 / 35ea49f79ac3c33503d067c8ee7804a25b62df1651dc398d40224d10d4d3b2fa  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.13"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_amd64.tar.gz"
      sha256 "c7b5e52c593f24daebc9a5c77843c90486618aad3919ecdd44e6958028746d0d"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_arm64.tar.gz"
      sha256 "af5b1d5a66fa0450534362bbcae3e7cc1363281e96bc92592d9a07d6003d3c59"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_Linux_amd64.tar.gz"
    sha256 "35ea49f79ac3c33503d067c8ee7804a25b62df1651dc398d40224d10d4d3b2fa"
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
