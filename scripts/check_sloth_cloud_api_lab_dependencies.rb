#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"
require "json"
require "open3"

root = File.expand_path("..", __dir__)
strict = ARGV.include?("--strict")
check_cluster_secret = ARGV.include?("--check-cluster-secret")
profile_arg = ARGV.find { |arg| arg.start_with?("--profile=") }
profile_name = profile_arg&.split("=", 2)&.last || "dev_real_write"

inventory_path = File.join(root, "inventory/sloth-cloud-api-lab-dependencies.yaml")
inventory = YAML.load_file(inventory_path)

sources = inventory.fetch("sources")
active_overlay = sources.fetch("active_overlay")
overlay_path = File.join(root, active_overlay)
configmap_path = File.join(root, sources.fetch("configmap"))
secret_name = sources.fetch("secret_name")
namespace = "sloth-labs"

def load_yaml_stream(text)
  text
    .split(/^---\s*$\n?/)
    .map do |chunk|
      next if chunk.strip.empty?

      YAML.safe_load(chunk, permitted_classes: [Date, Time], aliases: false)
    end
    .compact
end

def render_kustomize(path)
  kubectl = `command -v kubectl`.strip
  raise "kubectl is required to render #{path}" if kubectl.empty?

  output, status = Open3.capture2e(kubectl, "kustomize", path)
  raise "kubectl kustomize failed for #{path}:\n#{output}" unless status.success?

  load_yaml_stream(output)
end

rendered_docs = render_kustomize(overlay_path)
configmap = rendered_docs.find do |doc|
  doc.fetch("kind", nil) == "ConfigMap" && doc.dig("metadata", "name") == "sloth-cloud-api-lab-config"
end
deployment = rendered_docs.find do |doc|
  doc.fetch("kind", nil) == "Deployment" && doc.dig("metadata", "name") == "sloth-cloud-api-lab"
end

raise "Rendered overlay is missing sloth-cloud-api-lab ConfigMap." unless configmap
raise "Rendered overlay is missing sloth-cloud-api-lab Deployment." unless deployment

declared_config = inventory.fetch("config").keys
actual_config = configmap.fetch("data").keys

declared_secrets = inventory.fetch("secrets").keys
actual_secrets = declared_secrets

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

secret_refs = deployment
  .fetch("spec")
  .fetch("template")
  .fetch("spec")
  .fetch("containers")
  .flat_map { |container| Array(container["envFrom"]) }
  .map { |env_from| env_from.dig("secretRef", "name") }
  .compact
secret_ref_missing = !secret_refs.include?(secret_name)

cluster_secret_missing_keys = []
cluster_secret_not_checked = !check_cluster_secret
if check_cluster_secret
  output, status = Open3.capture2e(
    "kubectl",
    "-n",
    namespace,
    "get",
    "secret",
    secret_name,
    "-o",
    "json"
  )
  if status.success?
    cluster_secret_keys = JSON.parse(output).fetch("data", {}).keys
    cluster_secret_missing_keys = declared_secrets - cluster_secret_keys
  else
    cluster_secret_missing_keys = declared_secrets
  end
end

class_counts = Hash.new(0)
inventory.fetch("config").each_value { |meta| class_counts[meta.fetch("class")] += 1 }
inventory.fetch("secrets").each_value { |meta| class_counts[meta.fetch("class")] += 1 }
profile = inventory.fetch("profiles").fetch(profile_name)
operation_policy = inventory.fetch("operation_policy")

puts "Sloth Cloud API lab dependency check"
puts "Rendered overlay: #{active_overlay}"
puts "ConfigMap keys: #{actual_config.length}"
puts "Secret delivery: #{sources.fetch("secret_mode")}"
puts "Required Secret keys: #{declared_secrets.length}"
puts "Class counts: #{class_counts.sort.map { |key, value| "#{key}=#{value}" }.join(", ")}"
puts "Profile: #{profile_name} - #{profile.fetch("label")}"
puts

puts "Operation boundary:"
if operation_policy.fetch("destructive_dev_business_operations_are_accepted")
  puts "  Destructive development business operations: accepted"
else
  puts "  Destructive development business operations: blocked"
end

if operation_policy.fetch("project_code_mutation_is_accepted")
  puts "  Project code mutation: accepted"
else
  puts "  Project code mutation: blocked"
end
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
if placeholder_config.empty? && placeholder_images.empty?
  puts "Git placeholders: OK"
else
  puts "Git placeholders: need attention"
  placeholder_images.each do |name, image|
    puts "  container.#{name}.image=#{image}"
  end
  placeholder_config.each do |key, value|
    puts "  #{key}=#{value}"
  end
end

puts
if secret_ref_missing
  puts "Secret reference: missing #{secret_name} in Deployment envFrom"
else
  puts "Secret reference: OK"
end

if check_cluster_secret
  if cluster_secret_missing_keys.empty?
    puts "Cluster Secret keys: OK"
  else
    puts "Cluster Secret keys: need attention"
    cluster_secret_missing_keys.each { |key| puts "  #{secret_name}.#{key}=missing" }
  end
else
  puts "Cluster Secret keys: not checked; add --check-cluster-secret before real sync"
end

coverage_failed = !missing_config.empty? || !stale_config.empty? || !missing_secrets.empty? || !stale_secrets.empty?
readiness_failed = !placeholder_images.empty? ||
  !placeholder_config.empty? ||
  secret_ref_missing ||
  (strict && cluster_secret_not_checked) ||
  !cluster_secret_missing_keys.empty?

if coverage_failed || (strict && readiness_failed)
  exit 1
end
