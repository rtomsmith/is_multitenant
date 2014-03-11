
class Account < ActiveRecord::Base
  has_many :projects
end

class Project < ActiveRecord::Base
  is_multitenant :with_attribute => :account_id

  has_one :manager
  has_many :tasks

  validates_uniqueness_of :name
end

class Manager < ActiveRecord::Base
  is_multitenant :with_attribute => :account_id
  belongs_to :project
end

class Task < ActiveRecord::Base
  is_multitenant :with_attribute => :account_id

  belongs_to :project
  default_scope -> { where(:completed => nil).order("name") }

  validates_uniqueness_of :name
end

class UnscopedModel < ActiveRecord::Base
  validates_uniqueness_of :name
end

class AliasedTask < ActiveRecord::Base
  is_multitenant :with_attribute => :account_id

  belongs_to :project_alias, :class_name => "Project"
end

class UniqueTask < ActiveRecord::Base
  is_multitenant :with_attribute => :account_id

  belongs_to :project
  validates_uniqueness_of :name, scope: :user_defined_scope
end

class CustomForeignKeyTask < ActiveRecord::Base
  is_multitenant :with_attribute => :accountID
  validates_uniqueness_of :name
end

