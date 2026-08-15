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
#   81d8f9af0269a0cd3df999c2402b9f35c208062fe9a3625875affe9090832cd4 / 5d734fdd98ccd537c67ecbee42ae067565b43337d74c45a4c6a78e8068e5dda1 / 0d346b7597e77a5303b3d0cbcd9378b4a700e9924a55e5656c52c87c1592c9d7  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.13"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_amd64.tar.gz"
      sha256 "81d8f9af0269a0cd3df999c2402b9f35c208062fe9a3625875affe9090832cd4"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_arm64.tar.gz"
      sha256 "5d734fdd98ccd537c67ecbee42ae067565b43337d74c45a4c6a78e8068e5dda1"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_Linux_amd64.tar.gz"
    sha256 "0d346b7597e77a5303b3d0cbcd9378b4a700e9924a55e5656c52c87c1592c9d7"
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
