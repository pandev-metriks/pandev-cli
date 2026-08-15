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
#   2.4.12           semantic version, e.g. 2.5.0
#   v2.4.12-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   74075b4bb2ee681aca54df9dc0d83987d75d26f1565aa4fbbfff37eb09d6b072 / 2f0cdbed6ccc124e1f7a49a083ce52ed906824d533932853159fa62eb4afadc4 / 3cffb4eb558ed9af73502ef1bdd455d27a85002d3a0e053e053418c0f51b5ece  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.12"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.12-beta/pandev-cli-plugin_2.4.12_macOS_amd64.tar.gz"
      sha256 "74075b4bb2ee681aca54df9dc0d83987d75d26f1565aa4fbbfff37eb09d6b072"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.12-beta/pandev-cli-plugin_2.4.12_macOS_arm64.tar.gz"
      sha256 "2f0cdbed6ccc124e1f7a49a083ce52ed906824d533932853159fa62eb4afadc4"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.12-beta/pandev-cli-plugin_2.4.12_Linux_amd64.tar.gz"
    sha256 "3cffb4eb558ed9af73502ef1bdd455d27a85002d3a0e053e053418c0f51b5ece"
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
