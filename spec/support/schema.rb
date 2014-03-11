# Support for creating the test schema and seed data

def create_schema!
  ActiveRecord::Schema.define(:version => 1) do
    create_table :accounts, :force => true do |t|
      t.column :name, :string
      t.column :subdomain, :string
    end

    create_table :projects, :force => true do |t|
      t.column :name, :string
      t.column :account_id, :integer
    end

    create_table :managers, :force => true do |t|
      t.column :name, :string
      t.column :project_id, :integer
      t.column :account_id, :integer
    end

    create_table :tasks, :force => true do |t|
      t.column :name, :string
      t.column :account_id, :integer
      t.column :project_id, :integer
      t.column :completed, :boolean
    end

    create_table :countries, :force => true do |t|
      t.column :name, :string
    end

    create_table :unscoped_models, :force => true do |t|
      t.column :name, :string
    end

    create_table :aliased_tasks, :force => true do |t|
      t.column :name, :string
      t.column :project_alias_id, :integer
      t.column :account_id, :integer
    end

    create_table :unique_tasks, :force => true do |t|
      t.column :name, :string
      t.column :user_defined_scope, :string
      t.column :project_id, :integer
      t.column :account_id, :integer
    end

    create_table :custom_foreign_key_tasks, :force => true do |t|
      t.column :name, :string
      t.column :accountID, :integer
    end
  end
end

def clean_database!
end

