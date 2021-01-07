require "spec_helper"

module EventStore
  describe Aggregate do
    let(:aggregate_id)  { "014001A8" }
    let(:type)          { "fake_events" }
    let(:fake_snapshot) { double("Snapshot", exists?: true) }
    let(:fake_stream)   { double("EventStream") }

    before(:each) { allow(Snapshot).to receive(:new).and_return(fake_snapshot) }
    before(:each) { allow(EventStream).to receive(:new).and_return(fake_stream) }

    subject(:aggregate) { EventStore::Aggregate.new(aggregate_id, type) }

    describe "#count" do
      it "has tests"
    end

    describe "#ids" do
      it "has tests"
    end

    describe "#append" do
      it "has tests"
    end

    describe "#snapshot_exists?" do
      it "delegates to its snapshot" do
        expect(fake_snapshot).to receive(:exists?).and_return(true)
        expect(aggregate.snapshot_exists?).to eq(true)
      end

      it "does not build a snapshot" do
        expect(fake_snapshot).to_not receive(:snapshot) # :(
        aggregate.snapshot_exists?
      end
    end
  end
end
