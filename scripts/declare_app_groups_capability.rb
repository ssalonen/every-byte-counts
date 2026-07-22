#!/usr/bin/env ruby
# Declares the App Groups capability on the app and widget targets in the
# XcodeGen-generated project.
#
# Why this exists: XcodeGen wires the entitlements file (CODE_SIGN_ENTITLEMENTS)
# but never declares the App Groups *capability* on the targets — the generated
# project's TargetAttributes are empty. With the capability undeclared, Xcode's
# ProcessProductPackaging strips com.apple.security.application-groups out of the
# signed .xcent even though the entitlements file requests it and the
# provisioning profile authorises it, so the shipped binary loses the App Group
# (fi.mailhub.everybytecounts 1.3.6 (5) crashed on launch for exactly this).
#
# Enabling the capability here writes the same SystemCapabilities entry that
# Xcode's "Signing & Capabilities" editor would, which keeps Xcode from
# discarding the entitlement. Run after `xcodegen generate` and before archiving.
#
# Zero project dependencies beyond the `xcodeproj` gem (installed in CI).

require "xcodeproj"

project_path = ARGV[0] || "EveryByteCounts.xcodeproj"
# The App Groups capability key Xcode uses for iOS targets.
CAPABILITY = "com.apple.ApplicationGroups.iOS".freeze
TARGETS = %w[EveryByteCounts EveryByteCountsWidgetExtension].freeze

project = Xcodeproj::Project.open(project_path)
attributes = (project.root_object.attributes["TargetAttributes"] ||= {})

changed = []
project.targets.each do |target|
  next unless TARGETS.include?(target.name)
  target_attrs = (attributes[target.uuid] ||= {})
  capabilities = (target_attrs["SystemCapabilities"] ||= {})
  capabilities[CAPABILITY] = { "enabled" => "1" }
  changed << target.name
end

missing = TARGETS - changed
unless missing.empty?
  abort "error: targets not found in #{project_path}: #{missing.join(', ')}"
end

project.save
puts "Declared App Groups capability (#{CAPABILITY}) on: #{changed.join(', ')}"
