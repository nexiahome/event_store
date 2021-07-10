require 'event_store'
Sequel.migration do
  no_transaction

  event_store_table = Sequel.qualify(EventStore.schema, EventStore.table_name)

  up do
    alter_table(event_store_table) do
      drop_index :aggregate_id
      drop_index :occurred_at
      drop_index :version
    end
  end

  down do
    alter_table(event_store_table) do
      add_index :version
      add_index :occurred_at
      add_index :aggregate_id
    end
  end
end
