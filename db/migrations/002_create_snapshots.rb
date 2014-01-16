Sequel.migration do
  change do
    create_table(:event_store_snapshots) do
      primary_key :id
      String      :aggregate_id
      String      :aggregate_type
      bytea       :event_ids
    end
  end
end
