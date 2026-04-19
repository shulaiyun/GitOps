#!/usr/bin/env ruby
require "open3"
require "pathname"
require "yaml"
require "date"

root = Pathname.new(__dir__).join("..").expand_path
inventory_path = root.join("inventory/services.yaml")
inventory = YAML.safe_load(File.read(inventory_path), permitted_classes: [Date, Time], aliases: false)
services = inventory.fetch("services")

recorded_ids = services.map { |service| service.fetch("id") }
running_ids = services.select { |service| service["status"] == "running" }.map { |service| service.fetch("id") }

docker_output, docker_status = Open3.capture2("docker", "ps", "--format", "{{.Names}}")
if !docker_status.success?
  warn "Failed to run docker ps"
  exit 1
end

actual_ids = docker_output.lines.map(&:strip).reject(&:empty?)
missing = actual_ids - recorded_ids
stale_running = running_ids - actual_ids

puts "Recorded services: #{recorded_ids.count}"
puts "Running inventory entries: #{running_ids.count}"
puts "Actual running containers: #{actual_ids.count}"

unless missing.empty?
  warn "Missing inventory entries for running containers:"
  missing.each { |id| warn "  - #{id}" }
end

unless stale_running.empty?
  warn "Inventory marks these services as running, but docker does not show them:"
  stale_running.each { |id| warn "  - #{id}" }
end

exit((missing.empty? && stale_running.empty?) ? 0 : 1)
