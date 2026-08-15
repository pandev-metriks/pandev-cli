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
#   2.5.0           semantic version, e.g. 2.5.0
#   v2.5.0-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   f9db62b21f5274e57a02111f36ec624cb14b7dd60341d58fc67d39d1fbf22e6f / debbfc605640a00e4cc95f4541ac72e05ea452d7b228074a4422cea592408633 / f2f9134eef741fd7d17ab851b768e5713b05ec18597c6d8997e65705d341bba8  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.0"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_macOS_amd64.tar.gz"
      sha256 "f9db62b21f5274e57a02111f36ec624cb14b7dd60341d58fc67d39d1fbf22e6f"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_macOS_arm64.tar.gz"
      sha256 "debbfc605640a00e4cc95f4541ac72e05ea452d7b228074a4422cea592408633"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_Linux_amd64.tar.gz"
    sha256 "f2f9134eef741fd7d17ab851b768e5713b05ec18597c6d8997e65705d341bba8"
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
