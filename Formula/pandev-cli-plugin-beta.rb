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
#   0faf487cee8efa6cb8bf13585170ba930d0f9334141776bf65f2267dd871ccea / 4c24f730709cccf4e314d467c323867f320b74bb58d4609999204bfaa89c5c05 / ab8c307702b0d1895e29720ac104b518f8fa647fc64d895827d4ee7cf709f46d  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.4.13"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_amd64.tar.gz"
      sha256 "0faf487cee8efa6cb8bf13585170ba930d0f9334141776bf65f2267dd871ccea"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_macOS_arm64.tar.gz"
      sha256 "4c24f730709cccf4e314d467c323867f320b74bb58d4609999204bfaa89c5c05"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.4.13-beta/pandev-cli-plugin_2.4.13_Linux_amd64.tar.gz"
    sha256 "ab8c307702b0d1895e29720ac104b518f8fa647fc64d895827d4ee7cf709f46d"
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
