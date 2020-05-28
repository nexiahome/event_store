require "bundler/gem_tasks"
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:'spec:ci')

task :default => :'spec:ci'

desc "Seed the performance db with millions of events"
task :'db:seed:perf' do
  sh 'time bundle exec ruby spec/benchmark/seed_db.rb'
end

desc "Run the performance benchmarks on the performance db"
task :benchmark do
  sh 'bundle exec ruby spec/benchmark/bench.rb'
end

desc "migrate db"
task :'db:migrate' do
  begin
    sh 'createdb history_store'
  rescue
    #we don't care if it exists already, so don't fail
  end
  sh 'psql history_store < db/setup_db_user.sql'
end
