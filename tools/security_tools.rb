# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rbconfig"
require "rubygems/package"
require "zlib"
require_relative "commands"

module SecurityTools
  def self.manifest
    platform = "#{RbConfig::CONFIG.fetch('host_os').start_with?('darwin') ? 'darwin' : 'linux'}-" \
               "#{RbConfig::CONFIG.fetch('host_cpu')}"
    JSON.parse(File.read(File.join(__dir__, "security-tools.json"))).fetch(platform)
  end

  def self.executable(name)
    Development::ROOT.join("tmp/tools", manifest.fetch(name).fetch("sha256"), name).to_s
  end

  def self.install
    manifest.each do |name, asset|
      destination = executable(name)
      next if File.executable?(destination)

      FileUtils.mkdir_p(File.dirname(destination))
      archive = "#{destination}.tar.gz"
      download(asset, archive)
      extract(archive, destination, name)
      FileUtils.rm_f(archive)
    end
  end

  def self.download(asset, archive)
    Development.run("curl", "--proto", "=https", "--tlsv1.2", "--location", "--fail", "--silent",
                    "--show-error", "--output", archive, asset.fetch("url"))
    return if Digest::SHA256.file(archive).hexdigest == asset.fetch("sha256")

    raise "Security tool checksum mismatch: #{asset.fetch('url')}"
  end

  def self.extract(archive, destination, name)
    Zlib::GzipReader.open(archive) do |gzip|
      Gem::Package::TarReader.new(gzip).each do |entry|
        next unless entry.file? && File.basename(entry.full_name) == name

        File.binwrite(destination, entry.read)
        File.chmod(0o755, destination)
      end
    end
    raise "Missing executable in verified archive: #{name}" unless File.executable?(destination)
  end

  def self.run(name, *)
    path = executable(name)
    raise "Run bin/setup to install #{name}" unless File.executable?(path)

    Development.run(path, *)
  end
end

SecurityTools.install if $PROGRAM_NAME == __FILE__
