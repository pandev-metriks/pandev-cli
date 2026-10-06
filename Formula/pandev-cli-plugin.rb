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
#   2.5.19           semantic version, e.g. 2.5.0
#   v2.5.19               release tag hosting the assets, e.g. v2.5.0
#   39bc6380242e071c5fe34dcb4e4db62508f9590d1b534773f06867dd80514d0e / e1a3404e6271d107197a5c1b4d5d12db3a415580a255903cd890d8a2a10ecf42 / 800ba08076607fb75ab7dfda85d4dae91d4b3c266095f5c18c0e42416c55f7e0  asset checksums
class PandevCliPlugin < Formula
  desc "PanDev Metrics CLI"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.19"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.19/pandev-cli-plugin_2.5.19_macOS_amd64.tar.gz"
      sha256 "39bc6380242e071c5fe34dcb4e4db62508f9590d1b534773f06867dd80514d0e"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.19/pandev-cli-plugin_2.5.19_macOS_arm64.tar.gz"
      sha256 "e1a3404e6271d107197a5c1b4d5d12db3a415580a255903cd890d8a2a10ecf42"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.19/pandev-cli-plugin_2.5.19_Linux_amd64.tar.gz"
    sha256 "800ba08076607fb75ab7dfda85d4dae91d4b3c266095f5c18c0e42416c55f7e0"
  end

  # No `conflicts_with "pandev-cli-plugin-beta"`: to check it, brew loads the beta formula,
  # and since Homebrew 6.0 it refuses to load a formula from an untrusted tap — installing
  # the stable one by its full name failed on that refusal (PDM-4862). The installer removes
  # the other channel before installing, and brew's own link step still refuses to overwrite
  # the other formula's `pandev`.

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
