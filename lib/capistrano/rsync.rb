require File.expand_path("../rsync/version", __FILE__)
require File.expand_path("../rsync/scm/base", __FILE__)
require File.expand_path("../rsync/scm/git", __FILE__)
require File.expand_path("../rsync/scm/svn", __FILE__)

# NOTE: Please don't depend on tasks without a description (`desc`) as they
# might change between minor or patch version releases. They make up the
# private API and internals of Capistrano::Rsync. If you think something should
# be public for extending and hooking, please let me know!

rsync_cache = lambda do
  cache = fetch(:rsync_cache)
  cache = deploy_to + "/" + cache if cache && cache !~ /^\//
  cache
end

scm_instance = lambda do
  scm_class = Capistrano::Rsync::Scm.const_get(:"#{fetch(:rsync_scm).capitalize}")
  scm_class.new(self)
end

Rake::Task["load:defaults"].enhance ["rsync:defaults"]
Rake::Task["deploy:check"].enhance ["rsync:hook_scm"]
Rake::Task["deploy:updating"].enhance ["rsync:hook_scm"]


desc "Stage and rsync to the server (or its cache)."
task :rsync => %w[rsync:stage] do
  on roles(:all) do |role|
    user = role.user + "@" if !role.user.nil?

    rsync = %w[rsync]
    rsync.concat fetch(:rsync_options)
    rsync << fetch(:rsync_stage) + "/"
    rsync << "#{user}#{role.hostname}:#{rsync_cache.call || release_path}"

    Kernel.system *rsync
  end
end

namespace :rsync do
  desc "Load rsync default options."
  task :defaults do
    set :rsync_options, %w[--recursive --delete --delete-excluded  --exclude .git*]
    set :rsync_copy, "rsync --archive --acls --xattrs"
    
     # Scm to use.
    set :rsync_scm, "git"
    
     # Stage is used on your local machine for rsyncing from.
    set :rsync_stage, "tmp/deploy"
    
     # Cache is used on the server to copy files to from to the release directory.
    # Saves you rsyncing your whole app folder each time.  If you nil rsync_cache,
    # Capistrano::Rsync will sync straight to the release path.
    set :rsync_cache, "shared/deploy"
  end
  
   # internally needed by capistrano's "deploy.rake"
  task :set_current_revision do
    Dir.chdir fetch(:rsync_stage) do
      cmd = scm_instance.call.get_current_revision_cmd
      rev = `#{cmd}`
      set :current_revision, rev
    end
  end
  
  task :hook_scm do
    Rake::Task.define_task("#{scm}:check") do
      invoke "rsync:check"
    end

    Rake::Task.define_task("#{scm}:create_release") do
      invoke "rsync:release"
    end
  end

  task :check do
    # Everything's a-okay inherently!
  end

  desc "Create the stage repository in a local directory."
  task :create_stage do
    next if File.directory?(fetch(:rsync_stage))
    scm_instance.call.create_stage_cmds.each do |cmd|
      Kernel.system *cmd
    end
  end

  desc "Update and freshen the stage repository."
  task :stage => %w[create_stage] do
    Dir.chdir fetch(:rsync_stage) do
      scm_instance.call.update_stage_cmds.each do |cmd|
        Kernel.system *cmd
      end
    end
  end

  desc "Copy the code to the releases directory."
  task :release => %w[rsync] do
    # Skip copying if we've already synced straight to the release directory.
    next if !fetch(:rsync_cache)

    copy = %(#{fetch(:rsync_copy)} "#{rsync_cache.call}/" "#{release_path}/")
    on roles(:all).each do execute copy end
  end

  # Matches the naming scheme of git tasks.
  # Plus was part of the public API in Capistrano::Rsync <= v0.2.1.
  task :create_release => %w[release]
end
