cask "clawstatus" do
  version "0.5.0"
  sha256 "6db5e25c3ea8f6fdeb0afb2529345675d2af150f76a835e8733ef2e04b3569ef"

  url "https://github.com/tuann2/Clawstatus/releases/download/v#{version}/Clawstatus-#{version}-apple-silicon.dmg"
  name "Clawstatus"
  desc "Menu bar monitor for remaining Claude Code and Codex usage"
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

    Install and sign in to Claude Code, Codex CLI, or both. Use Clawstatus
    Settings to choose which installed providers are displayed and polled.
  EOS
end
