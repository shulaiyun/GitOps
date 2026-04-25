#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

root = File.expand_path("..", __dir__)
strict = ARGV.include?("--strict")

inventory_path = File.join(root, "inventory/sloth-cloud-api-lab-dependencies.yaml")
inventory = YAML.load_file(inventory_path)

configmap_path = File.join(root, inventory.fetch("sources").fetch("configmap"))
external_secret_path = File.join(root, inventory.fetch("sources").fetch("external_secret"))
deployment_path = File.join(root, inventory.fetch("sources").fetch("deployment"))

configmap = YAML.load_file(configmap_path)
external_secret = YAML.load_file(external_secret_path)
deployment = YAML.load_file(deployment_path)

declared_config = inventory.fetch("config").keys
actual_config = configmap.fetch("data").keys

declared_secrets = inventory.fetch("secrets").keys
actual_secrets = external_secret.fetch("spec").fetch("data").map { |item| item.fetch("secretKey") }

missing_config = actual_config - declared_config
stale_config = declared_config - actual_config
missing_secrets = actual_secrets - declared_secrets
stale_secrets = declared_secrets - actual_secrets

placeholder_config = configmap.fetch("data").select do |_key, value|
  value.to_s.include?("replace-me")
end

placeholder_images = deployment
  .fetch("spec")
  .fetch("template")
  .fetch("spec")
  .fetch("containers")
  .map { |container| [container.fetch("name"), container.fetch("image")] }
  .select { |_name, image| image.include?("replace-me") }

secret_store_name = external_secret.fetch("spec").fetch("secretStoreRef").fetch("name")
secret_store_placeholder = secret_store_name.include?("replace-me")

class_counts = Hash.new(0)
inventory.fetch("config").each_value { |meta| class_counts[meta.fetch("class")] += 1 }
inventory.fetch("secrets").each_value { |meta| class_counts[meta.fetch("class")] += 1 }

puts "Sloth Cloud API lab dependency check"
puts "ConfigMap keys: #{actual_config.length}"
puts "ExternalSecret keys: #{actual_secrets.length}"
puts "Class counts: #{class_counts.sort.map { |key, value| "#{key}=#{value}" }.join(", ")}"
puts

if missing_config.empty? && stale_config.empty? && missing_secrets.empty? && stale_secrets.empty?
  puts "Inventory coverage: OK"
else
  puts "Inventory coverage: needs attention"
  puts "  Config keys missing from inventory: #{missing_config.join(", ")}" unless missing_config.empty?
  puts "  Inventory config keys not in ConfigMap: #{stale_config.join(", ")}" unless stale_config.empty?
  puts "  Secret keys missing from inventory: #{missing_secrets.join(", ")}" unless missing_secrets.empty?
  puts "  Inventory secret keys not in ExternalSecret: #{stale_secrets.join(", ")}" unless stale_secrets.empty?
end

puts
if placeholder_config.empty? && !secret_store_placeholder
  if placeholder_images.empty?
    puts "First-sync placeholders: OK"
  else
    puts "First-sync blockers:"
    placeholder_images.each do |name, image|
      puts "  container.#{name}.image=#{image}"
    end
  end
else
  puts "First-sync blockers:"
  placeholder_images.each do |name, image|
    puts "  container.#{name}.image=#{image}"
  end
  placeholder_config.each do |key, value|
    puts "  #{key}=#{value}"
  end
  puts "  secretStoreRef.name=#{secret_store_name}" if secret_store_placeholder
end

coverage_failed = !missing_config.empty? || !stale_config.empty? || !missing_secrets.empty? || !stale_secrets.empty?
readiness_failed = !placeholder_images.empty? || !placeholder_config.empty? || secret_store_placeholder

if coverage_failed || (strict && readiness_failed)
  exit 1
end
