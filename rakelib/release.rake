# frozen_string_literal: true

require_relative "../tools/release"

desc <<~DESC
  Release the gem and the npm package at VERSION (default: the newest CHANGELOG.md section).

  Requires a merged version-bump PR: the version file, both package.json files and a dated
  CHANGELOG.md section must already match VERSION. The task never commits to main. It checks
  git and CI, runs npm login and gem signin when either registry has no credentials, validates and packages HEAD in a clean worktree, asks you to type the
  version, tags HEAD, runs gem push and npm publish (each asks for a one-time password), verifies
  both registries, pushes the tag and creates the GitHub release. Rerunning resumes a partial
  release: a registry that already has identical bytes is skipped.

  bundle exec rake "release[,true]"       # dry run of the newest CHANGELOG version
  bundle exec rake "release[0.1.0]"       # live release
DESC
task :release, %i[version dry_run] do |_task, args|
  Release.release(args[:version], dry_run: args[:dry_run].to_s == "true")
end

desc <<~DESC
  Create or update the GitHub release for an already pushed tag from its CHANGELOG.md section.

  bundle exec rake "sync_github_release[0.1.0]"
DESC
task :sync_github_release, %i[version dry_run] do |_task, args|
  Release.sync_github_release(args[:version], dry_run: args[:dry_run].to_s == "true")
end
