lib = File.expand_path('../../../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rspec'
require 'event_store'
require 'benchmark'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.on("-c","--connection","Connection string") do |c|
    options[:connection_string] = c
  end
end.parse!

if !options[:connection_string]
  puts "You need to set connection string with the -c flag"
  puts "Ex. ruby bench.rb -c vertica://user:pw@host:port/db_name"
  exit 1
end

EventStore.connect ARGV.first

ITERATIONS = 100

Benchmark.bmbm do |x|
  x.report 'Read time' do
    ITERATIONS.times do
      EventStore::Client.new(rand(300) + 1, :device).current_state
    end
  end
end
