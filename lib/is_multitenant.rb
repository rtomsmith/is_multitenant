require 'scope_injector'

module Multitenant

  # Use this method to set the current tenant id. Typically this would be called from
  # a controller. For example:
  #
  #   class ApplicationController < ActionController::Base
  #     before_filter :set_the_current_tenant
  #
  #     def set_the_current_tenant
  #       Multitenant.current_tenant_id = current_user.account_id
  #     end
  #   end
  #
  def self.current_tenant_id=(tenant_id)
    Thread.current[:current_tenant_id] = tenant_id
  end

  # Returns the currently set tenant id. Used by models to scope operations.
  def self.current_tenant_id
    Thread.current[:current_tenant_id] ||= (defined?(Rails::Console) ? Account.first.id : nil)
  end

  # Sometimes you need to execute code in the scope of a tenant is different
  # than the current tenant. This can be useful for admin tasks in Rake, or
  # in tests. For example:
  #
  #   Multitenant.with_tenant_id(override_tenant_id) do
  #     ...do some AR stuff...
  #   end
  #
  # forces the specified tenant id to be used to scope all the ActiveRecord
  # operations inside the block.
  #
  def self.with_tenant_id(tenant_id)
    begin
      old_tenant, self.current_tenant_id = self.current_tenant_id, tenant_id
      yield
    ensure
      self.current_tenant_id = old_tenant
    end
  end

  # Disables the multitenant scoping for all model operations within the block. The
  # scoping is temporarily disabled for ALL model classes involved.
  def self.without_multitenant_scope(&blk)
    ScopeInjector.without_injected_scope(:multitenant, &blk)
  end


  # Add support to ActiveRecord::Base for the +is_mulitenant+ macro
  module IsMultitenant

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      # When invoked from an ActiveRecord model class, +is_multitenant+ specifies
      # that the model's database operations always be scoped to the application
      # request's current tenant. Usage is as follows:
      #
      #   class Contact < ActiveRecord::Base
      #     is_multitenant :with_attribute => :account_id
      #         -OR-
      #     is_multitenant :class => :account
      #        -OR-
      #     is_multitenant :class => :account, :with_attribute => :account_key
      #   end
      #
      def is_multitenant(options = {})
        raise 'Cannot use is_multitenant more than once per model class' if is_multitenant?

        cattr_accessor :tenant_class_name
        cattr_accessor :tenant_attribute

        self.tenant_attribute = options[:with_attribute]
        raise ArgumentError, "Must specify :class and/or :with_attribute" if options[:class].blank? && self.tenant_attribute.blank?
        class_name = self.tenant_attribute.to_s.ends_with?('_id') ? self.tenant_attribute.to_s.sub('_id','').underscore.to_sym : nil
        self.tenant_class_name = (options[:class] || class_name).to_s.classify
        self.tenant_attribute = self.tenant_class_name.foreign_key.to_sym if self.tenant_attribute.nil?

        extend  IsMultitenant::SingletonMethods
        include IsMultitenant::InstanceMethods

        inject_scope :multitenant, :for_current_tenant, :apply_to => :all

        scope :for_current_tenant, ->() { where(tenant_condition) }
        scope :for_tenant, ->(tenant_id) { where(tenant_condition(tenant_id)) }

        validate :associations_have_same_tenant

        before_validation :force_current_tenant_id
        before_save :force_current_tenant_id

        define_tenant_id_writer(tenant_attribute)
      end

      def is_multitenant?
        false
      end
    end

    # These methods are available as class level methods to the models that
    # invoke is_multitenant, and only to those models.
    module SingletonMethods

      public

        def is_multitenant?
          true
        end

        def tenant_condition(tenant_id = nil)
          raise 'ERROR: the current tenant id has not been set' unless tenant_id || current_tenant_id
          {self.tenant_attribute => tenant_id || current_tenant_id}
        end

        def current_tenant_id
          Multitenant.current_tenant_id
        end

      private

        def define_tenant_id_writer(tenant_attribute)
          define_method("#{tenant_attribute}=") do |value|
            if self.class.without_multitenant_scope? || new_record? || send(tenant_attribute).nil?
              write_attribute(:"#{tenant_attribute}", value)
            else
              raise "Unauthorized assignment to :#{tenant_attribute}. This field is protected by is_multitenant and is set automatically."
            end
          end
        end

    end

    # All instances of is_multitenant models have access to the following
    # methods.
    module InstanceMethods
      def self.included(base)

        protected

          def set_tenant_id(tenant_id = nil)
            write_attribute(self.class.tenant_attribute, tenant_id || self.class.current_tenant_id)
          end

          def force_current_tenant_id
            set_tenant_id unless self.class.without_multitenant_scope?
          end

          def associations_have_same_tenant
            self.class.reflect_on_all_associations(:belongs_to).each do |assoc|
              if assoc.klass.is_multitenant? && assoc.class_name != self.tenant_class_name
                value = send(assoc.foreign_key)
                errors.add assoc.foreign_key, "multitenant association #{assoc.name} has different tenant" unless value.nil? || assoc.klass.where(:id => value).exists?
              end
            end
          end

      end
    end

  end
end

ActiveRecord::Base.send :include, Multitenant::IsMultitenant
