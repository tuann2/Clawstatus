cask "clawstatus" do
  version "0.4.1"
  sha256 "614d2d998daaa24c72fb85d455331056f4286af84fef7f9e7582dcecf5998b13"

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
