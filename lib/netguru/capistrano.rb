# Defines netguru custom task to deploy project.
require 'open-uri'
require 'capistrano'

module Netguru
  module Capistrano
    def self.load_into(configuration)
      configuration.load do

        $:.unshift(File.expand_path('./lib', ENV['rvm_path']))
        require 'rvm/capistrano'
        require 'bundler/capistrano'
        require 'open-uri'


        set :repository,  "git@github.com:netguru/#{application}.git"

        set :stage, 'staging' unless exists?(:stage)
        set(:rails_env) { fetch(:stage) }
        set :user, application
        set(:deploy_to) { "/home/#{fetch(:user)}/app" }

        branches = {:production => :qa, :qa => :staging, :staging => :master}
        set(:branch) { branches[fetch(:stage).to_sym].to_s }

        role(:db, :primary => true) { fetch(:webserver) }
        role(:app) { fetch(:webserver) }
        role(:web) { fetch(:webserver) }

        set :remote, "origin"
        set(:current_revision)  { capture("cd #{current_path}; git rev-parse HEAD").strip }

        set :scm, :git

        set(:latest_release)  { fetch(:current_path) }
        set(:release_path)    { fetch(:current_path) }
        set(:current_release) { fetch(:current_path) }

        set(:runner) { "RAILS_ENV=#{fetch(:stage)} bundle exec" }

        namespace :deploy do
          desc "Setup a GitHub-style deployment."
          task :setup, :except => { :no_release => true } do
            dirs = [deploy_to, shared_path]
            dirs += shared_children.map { |d| File.join(shared_path, d) }
            run "mkdir -p #{dirs.join(' ')} && chmod g+w #{dirs.join(' ')}"
            run "ssh-keyscan github.com >> /home/#{user}/.ssh/known_hosts"
            run "git clone #{repository} #{current_path}"
            run "cd #{current_path} && git checkout -b #{stage} ; git merge #{remote}/#{branch}; git push #{remote} #{stage}"
          end

          task :symlink do
          end

          task :migrate do
          end

          desc "Update the deployed code"
          task :update_code, :except => { :no_release => true } do
            run "cd #{current_path} && git fetch #{remote} && git checkout #{stage} -f && git merge #{remote}/#{branch} && git push #{remote} #{stage}"
          end

          desc "Restarts app"
          task :restart, :except => { :no_release => true } do
            run "touch #{current_path}/tmp/restart.txt"
          end
        end

        namespace :netguru do
          #restart solr server
          task :start_solr do
            run("cd #{current_path} && #{runner} rake sunspot:solr:start ;true")
          end
          #update whenever
          task :update_crontab, :roles => :web do
            run "cd #{current_path} && #{runner} whenever --update-crontab #{application} --set environment=#{fetch(:stage)}" if ["qa", "production"].include? fetch(:stage)
          end
          #restart DJ
          task :restart_dj do
            run "cd #{current_path}; #{runner} script/delayed_job restart"
          end
          #precompile assets
          task :precompile do
            run "cd #{current_path} && #{runner} rake assets:precompile"
          end
          #backup db
          task :backup do
            run("cd #{current_path} && astrails-safe -v config/safe.rb --local") if stage == 'production' or stage == 'beta'
          end
          #notify ab
          task :notify_airbrake do
            run "cd #{current_path} && #{runner} rake airbrake:deploy TO=#{stage} REVISION=#{current_revision} REPO=#{repository}"
          end

          #ask sc
          task :secondcoder do
            standup_response = open("http://secondcoder.com/api/netguru/#{application}/check").read
            raise "Computer says no!\n#{standup_response}" unless standup_response == "OK"
          end

        end

      end
    end
  end
end


if Capistrano::Configuration.instance
  Netguru::Capistrano.load_into(Capistrano::Configuration.instance)
end
