require 'rspec'
require 'event_store'
require 'benchmark'

EventStore.connect :adapter => :postgres, :database => 'event_store_performance', :host => 'localhost'

ITERATIONS = 100_000

Benchmark.bmbm do |x|
  x.report 'Read time' do
    ITERATIONS.times do
      EventStore::Client.new(rand(300) + 1, :device).current_state
    end
  end
end
