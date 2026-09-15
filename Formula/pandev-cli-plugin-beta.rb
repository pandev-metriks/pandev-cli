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
#   2.5.14           semantic version, e.g. 2.5.0
#   v2.5.14-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   2b641ff6fdb78a84e5620555aa42ae60845c732f00d83aa7e31bbc66eb26c6c0 / 7819aec44b0df0e112f679d4ff6f06b5a36517460f3c24bb6a12c71966c44531 / 59e4b62fb1a0b5f57a6afeb928fce3ba77f9defa12f6ff4d9bd378001a20f01b  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.14"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.14-beta/pandev-cli-plugin_2.5.14_macOS_amd64.tar.gz"
      sha256 "2b641ff6fdb78a84e5620555aa42ae60845c732f00d83aa7e31bbc66eb26c6c0"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.14-beta/pandev-cli-plugin_2.5.14_macOS_arm64.tar.gz"
      sha256 "7819aec44b0df0e112f679d4ff6f06b5a36517460f3c24bb6a12c71966c44531"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.14-beta/pandev-cli-plugin_2.5.14_Linux_amd64.tar.gz"
    sha256 "59e4b62fb1a0b5f57a6afeb928fce3ba77f9defa12f6ff4d9bd378001a20f01b"
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
