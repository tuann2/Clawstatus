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
    Clawstatus is ad-hoc signed and not Apple-notarized. Homebrew verifies the
    pinned SHA-256, but macOS quarantine must be removed from this app once
    after install or upgrade:

      xattr -dr com.apple.quarantine /Applications/Clawstatus.app

    Claude Code must already be installed, updated, and signed in.
  EOS
end
