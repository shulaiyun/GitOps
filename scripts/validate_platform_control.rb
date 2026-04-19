#!/usr/bin/env ruby
require "open3"
require "pathname"
require "yaml"
require "date"

root = Pathname.new(__dir__).join("..").expand_path

required_files = [
  root.join("inventory/services.yaml"),
  root.join("inventory/compose-projects.yaml"),
  root.join("inventory/uptime-targets.yaml"),
  root.join("environments/lab-compose/platform.yaml"),
  root.join("environments/lab-k3s/platform.yaml"),
  root.join("tenants/example-managed/tenant.yaml"),
  root.join("stacks/platform-core/compose.yaml")
]

missing_files = required_files.reject(&:exist?)
unless missing_files.empty?
  warn "Missing required files:"
  missing_files.each { |path| warn "  - #{path}" }
  exit 1
end

yaml_files = root.glob("**/*.yaml")
yaml_files.each do |file|
  YAML.safe_load(File.read(file), permitted_classes: [Date, Time], aliases: false)
end

compose_cmd = ["docker", "compose", "-f", root.join("stacks/platform-core/compose.yaml").to_s, "config"]
compose_output, compose_status = Open3.capture2e(*compose_cmd)
unless compose_status.success?
  warn compose_output
  exit 1
end

coverage_cmd = ["ruby", root.join("scripts/check_inventory_coverage.rb").to_s]
coverage_output, coverage_status = Open3.capture2e(*coverage_cmd)
puts coverage_output
unless coverage_status.success?
  exit 1
end

puts "Platform control validation passed."
