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
#   e792fbaede541a9cdf4dc083080577041b3c8942e6cb23748198d16b376481ae / a9bf39487a7abf54f10c86a98fbd40c3c81b1867a116fbfac61f82dfcfc41b2e / 917877ff5e713f024a114e37ba783d6aa47093de5cd5d30123b4b07f6734af43  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.0"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_macOS_amd64.tar.gz"
      sha256 "e792fbaede541a9cdf4dc083080577041b3c8942e6cb23748198d16b376481ae"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_macOS_arm64.tar.gz"
      sha256 "a9bf39487a7abf54f10c86a98fbd40c3c81b1867a116fbfac61f82dfcfc41b2e"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.0-beta/pandev-cli-plugin_2.5.0_Linux_amd64.tar.gz"
    sha256 "917877ff5e713f024a114e37ba783d6aa47093de5cd5d30123b4b07f6734af43"
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
