# Pins the fastlane toolchain so CI and local machines resolve the same gems.
# Exact versions are locked in Gemfile.lock; Dependabot proposes updates weekly
# (.github/dependabot.yml).
source "https://rubygems.org"

# fastlane is build-time tooling — it never ships in the app — so it lives in the
# :development group. Dependency review (fail-on-scopes: runtime) then only
# *blocks* on dependencies that actually ship, and merely reports on this
# toolchain: its licenses don't bind the distributed app, and CI-tool CVEs are
# surfaced without gating merges. CI installs all groups, so `fastlane` still runs.
group :development do
  gem "fastlane"
end
