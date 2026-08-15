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
#   856f57b0368d3a23db922f4e38a481c9266e10e3b015f32532a8e5fcc17e9dee / 5cac8aaf34b7e2d41b75d3612881c0199f2cb16a24de68e2be6aabc837397dd7 / e11c9c7eb21778d5166259e49e84191d799131f6cdbcbb313138b17d77c1740d  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.13"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_amd64.tar.gz"
      sha256 "856f57b0368d3a23db922f4e38a481c9266e10e3b015f32532a8e5fcc17e9dee"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_arm64.tar.gz"
      sha256 "5cac8aaf34b7e2d41b75d3612881c0199f2cb16a24de68e2be6aabc837397dd7"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_Linux_amd64.tar.gz"
    sha256 "e11c9c7eb21778d5166259e49e84191d799131f6cdbcbb313138b17d77c1740d"
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
