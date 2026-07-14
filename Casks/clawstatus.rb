cask "clawstatus" do
  version "0.3.0"
  sha256 "1178af33c86087a4249208e247175e4924a1847bd97792d7757e9d6f869149a2"

  url "https://github.com/tuann2/Clawstatus/releases/download/v#{version}/Clawstatus-#{version}-apple-silicon.dmg"
  name "Clawstatus"
  desc "Menu bar monitor for remaining Claude Code usage"
  homepage "https://github.com/tuann2/Clawstatus"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Clawstatus.app"

  zap trash: "~/Library/Application Support/Clawstatus"

  caveats <<~EOS
    Clawstatus is ad-hoc signed and not Apple-notarized. Install this cask with
    HOMEBREW_CASK_OPTS=--no-quarantine only if you trust this repository and
    have verified that Homebrew accepted the pinned SHA-256 checksum.

    Claude Code must already be installed, updated, and signed in.
  EOS
end
