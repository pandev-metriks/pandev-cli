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
#   2.5.17           semantic version, e.g. 2.5.0
#   v2.5.17-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   ede9508355c9c8269b09ad31e0a4e82da7d7b958752e283adf08ce08d4981b55 / d8250cbe7a86a04c21a93d21925abe3aac42a6035f464fd63fe7bc73389f4e2d / 573dde869eba1700182b3b17ca7674e3808735f0dff45979b18630aece85cf79  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.17"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.17-beta/pandev-cli-plugin_2.5.17_macOS_amd64.tar.gz"
      sha256 "ede9508355c9c8269b09ad31e0a4e82da7d7b958752e283adf08ce08d4981b55"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.17-beta/pandev-cli-plugin_2.5.17_macOS_arm64.tar.gz"
      sha256 "d8250cbe7a86a04c21a93d21925abe3aac42a6035f464fd63fe7bc73389f4e2d"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.17-beta/pandev-cli-plugin_2.5.17_Linux_amd64.tar.gz"
    sha256 "573dde869eba1700182b3b17ca7674e3808735f0dff45979b18630aece85cf79"
  end

  # No `conflicts_with "pandev-cli-plugin"`: to check it, brew loads the stable formula, and
  # since Homebrew 6.0 it refuses to load a formula from an untrusted tap — installing the
  # beta by its full name failed on that refusal (PDM-4862). The installer removes the other
  # channel before installing, and brew's own link step still refuses to overwrite the other
  # formula's `pandev`.

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
