#!/usr/bin/env ruby

require 'yaml'
require 'pathname'
require 'date'

ROOT = Pathname.new(__dir__).join('..').expand_path
K8S_DIR = ROOT.join('k8s')

yaml_files = Dir.glob(K8S_DIR.join('**', '*.yaml')).sort
raise 'No Kubernetes YAML files found.' if yaml_files.empty?

document_count = 0
kustomizations = []

yaml_files.each do |file|
  docs = File.read(file)
    .split(/^---\s*$\n?/)
    .map do |chunk|
      next if chunk.strip.empty?
      YAML.safe_load(chunk, permitted_classes: [Date, Time], aliases: false)
    end.compact
  docs.compact.each do |doc|
    unless doc.is_a?(Hash)
      raise "Unexpected YAML document in #{file}"
    end
    document_count += 1
  end
  kustomizations << file if File.basename(file) == 'kustomization.yaml'
end

kustomizations.each do |file|
  dir = Pathname.new(file).dirname
  config = YAML.safe_load(File.read(file), permitted_classes: [Date, Time], aliases: false) || {}
  Array(config['resources']).each do |resource|
    next if resource.start_with?('http://', 'https://')
    target = dir.join(resource)
    raise "Missing kustomize resource #{resource} referenced by #{file}" unless target.exist?
  end
end

puts "Kubernetes YAML files: #{yaml_files.count}"
puts "Kubernetes documents: #{document_count}"
puts "Kustomizations checked: #{kustomizations.count}"
puts 'Kubernetes manifest validation passed.'
