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
#   2.5.21           semantic version, e.g. 2.5.0
#   v2.5.21-beta               release tag hosting the assets, e.g. v2.5.0-beta
#   36de21353c06b82cff8e2539604e3d54f7328b2c3c5fc64cd7bbd8678b8aa58b / 0d37a1f707a315a7c6d6c11a1dcf4d205d587181e23570a404cd435e4273b059 / 2eeefdd5bb3bdb4d35d307b34d812e525c609fa0e3607f656848cd7c9e382982  asset checksums
class PandevCliPluginBeta < Formula
  desc "PanDev Metrics CLI (beta channel)"
  homepage "https://github.com/pandev-metriks/pandev-cli"
  version "2.5.21"

  depends_on "jq"
  depends_on "git"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21-beta/pandev-cli-plugin_2.5.21_macOS_amd64.tar.gz"
      sha256 "36de21353c06b82cff8e2539604e3d54f7328b2c3c5fc64cd7bbd8678b8aa58b"
    else
      url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21-beta/pandev-cli-plugin_2.5.21_macOS_arm64.tar.gz"
      sha256 "0d37a1f707a315a7c6d6c11a1dcf4d205d587181e23570a404cd435e4273b059"
    end
  end

  on_linux do
    url "https://github.com/pandev-metriks/pandev-cli/releases/download/v2.5.21-beta/pandev-cli-plugin_2.5.21_Linux_amd64.tar.gz"
    sha256 "2eeefdd5bb3bdb4d35d307b34d812e525c609fa0e3607f656848cd7c9e382982"
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
