cask "clawstatus" do
  version "0.4.0"
  sha256 "5a9ce5a581bd78d47b7c61bb6a2af75c0a5f6b226d6593f4bb593a0da89d4191"

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

    Install and sign in to Claude Code, Codex CLI, or both. Clawstatus shows
    whichever providers are available.
  EOS
end
