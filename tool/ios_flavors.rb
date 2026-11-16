# Creates iOS build configurations and shared schemes for each environment
# flavor, so `flutter run/build ios --flavor <env>` works (and the
# `default-flavor: local` in pubspec.yaml does not break iOS builds).
#
#   ruby tool/ios_flavors.rb && (cd ios && pod install)
#
# Idempotent: re-run it after adding a flavor to FLAVORS. For each flavor it
# adds Debug-<flavor>, Release-<flavor> and Profile-<flavor> configurations
# (copied from Debug/Release/Profile) to the project and every target, sets
# a per-flavor display name and bundle id on the Runner target, and writes
# ios/Runner.xcodeproj/xcshareddata/xcschemes/<flavor>.xcscheme.
require 'xcodeproj'

FLAVORS = {
  'local' => { name: 'Enrolly Local', suffix: '.local' },
  'development' => { name: 'Enrolly Dev', suffix: '.dev' },
  'qa' => { name: 'Enrolly QA', suffix: '.qa' },
  'production' => { name: 'Enrolly', suffix: '' },
}.freeze
BASES = %w[Debug Release Profile].freeze

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

def ensure_config(list, base_name, new_name)
  existing = list.build_configurations.find { |c| c.name == new_name }
  return existing if existing
  base = list.build_configurations.find { |c| c.name == base_name }
  raise "Missing #{base_name} configuration" unless base
  config = list.project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  config.name = new_name
  config.build_settings = Marshal.load(Marshal.dump(base.build_settings))
  config.base_configuration_reference = base.base_configuration_reference
  list.build_configurations << config
  config
end

runner = project.targets.find { |t| t.name == 'Runner' }
flutter_group = project.main_group.children.find { |g| g.display_name == 'Flutter' }

# Per-flavor xcconfig for the Runner target: the matching CocoaPods config
# plus Flutter's generated settings (mirrors Flutter/Debug.xcconfig).
def flavor_xcconfig(root, group, base, flavor)
  file_name = "#{base}-#{flavor}.xcconfig"
  pods = "Pods-Runner.#{base.downcase}-#{flavor}.xcconfig"
  File.write(File.join(root, 'ios', 'Flutter', file_name),
             "#include? \"Pods/Target Support Files/Pods-Runner/#{pods}\"\n#include \"Generated.xcconfig\"\n")
  target_path = File.join(root, 'ios', 'Flutter', file_name)
  # Drop references from earlier runs that point at the wrong location.
  group.files.select { |f| f.path == file_name && f.real_path.to_s != target_path }.each(&:remove_from_project)
  # The Flutter group has no path of its own; files are listed as Flutter/<name>.
  group.files.find { |f| f.real_path.to_s == target_path } || group.new_reference("Flutter/#{file_name}")
end
base_bundle_id = runner.build_configurations.find { |c| c.name == 'Release' }
                       .build_settings['PRODUCT_BUNDLE_IDENTIFIER']

FLAVORS.each do |flavor, meta|
  BASES.each do |base|
    name = "#{base}-#{flavor}"
    ensure_config(project.build_configuration_list, base, name)
    project.targets.each do |target|
      config = ensure_config(target.build_configuration_list, base, name)
      next unless target == runner
      config.base_configuration_reference = flavor_xcconfig(root, flutter_group, base, flavor)
      config.build_settings['APP_DISPLAY_NAME'] = meta[:name]
      config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{base_bundle_id}#{meta[:suffix]}"
    end
  end
end
# Plain (flavorless) configurations keep the default name.
runner.build_configurations.each do |c|
  c.build_settings['APP_DISPLAY_NAME'] ||= 'Enrolly'
end
project.save

template = File.read(File.join(project_path, 'xcshareddata', 'xcschemes', 'Runner.xcscheme'))
FLAVORS.each_key do |flavor|
  scheme = template.gsub(/buildConfiguration = "(Debug|Release|Profile)"/) { %(buildConfiguration = "#{$1}-#{flavor}") }
  File.write(File.join(project_path, 'xcshareddata', 'xcschemes', "#{flavor}.xcscheme"), scheme)
end

puts "iOS flavors configured: #{FLAVORS.keys.join(', ')}"
