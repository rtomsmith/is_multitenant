require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Multitenant do
  before { Multitenant.current_tenant_id = 1 }
  after { Multitenant.current_tenant_id = nil }

  # Setting and getting
  describe 'setting the current tenant id' do
    before { Multitenant.current_tenant_id = 9876 }
    it { expect(Multitenant.current_tenant_id).to eq(9876) }
  end

  describe 'models should report support for multi-tenancy' do
    it {Project.is_multitenant?.should be_true}
    it {Project.respond_to?(:inject_scope_multitenant?).should be_true}
    it {UnscopedModel.is_multitenant?.should_not be_true}
  end

  describe "tenant required" do
    describe "raises exception if no tenant specified" do
      before do
        @account1 = Account.create!(:name => 'foo')
        Multitenant.current_tenant_id = @account1.id
        @project1 = @account1.projects.create!(:name => 'foobar')
      end

      it "should raise an error when no tenant is provided" do
        Multitenant.current_tenant_id = nil
        expect { Project.all.to_a }.to raise_error(RuntimeError, /current tenant/)
      end
    end
  end

  describe 'tenant_id should be immutable, if already set' do
    before do
      @account = Account.create!(:name => 'Test account')
      Multitenant.current_tenant_id = @account.id
      @project = @account.projects.create!(:name => 'Test project')
    end

    it { running {@project.account_id = @account.id + 1}.should raise_error }
  end

  describe 'tenant_id should be mutable, if not already set' do
    before do
      @account = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = @account.id
      @project = Project.create!(:name => 'bar')
      @project.update_column('account_id', nil)
    end

    it { @project.account_id.should be_nil }
    it { running { @project.account_id = @account.id }.should_not raise_error }
  end

  describe 'allows custom foreign_key on is_multitenant' do
    before do
      @account  = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = @account.id
      @custom_foreign_key_task = CustomForeignKeyTask.create!(:name => 'foo')
    end

    it { @custom_foreign_key_task.accountID.should == @account.id }
  end

  # Scoping models
  describe 'Project.all should be scoped to the current tenant if set' do
    before do
      @account1 = Account.create!(:name => 'foo')
      @account2 = Account.create!(:name => 'bar')

      Multitenant.current_tenant_id = @account1.id
      @project1 = @account1.projects.create!(:name => 'foobar')
      Multitenant.current_tenant_id = @account2.id
      @project2 = @account2.projects.create!(:name => 'baz')

      Multitenant.current_tenant_id = @account1.id
      @projects = Project.all
    end

    it { @projects.length.should == 1 }
    it { @projects.should == [@project1] }
  end

  describe 'unscoping operations should work' do
    before do
      @account1 = Account.create!(:name => 'foo')
      @account2 = Account.create!(:name => 'bar')

      Multitenant.current_tenant_id = @account1.id
      @project1 = @account1.projects.create!(:name => 'foobar')
      Multitenant.current_tenant_id = @account2.id
      @project2 = @account2.projects.create!(:name => 'baz')

      Multitenant.current_tenant_id = @account1.id
      @projects_unscoped = Project.unscoped.all
      @projects_without_multitenant_scope = Project.without_multitenant_scope{Project.all}
    end

    it { @projects_unscoped.count.should == 1 }       # unscoping default_scope should have no affect
    it { @projects_without_multitenant_scope.count.should == 2 }
  end

  describe 'Associations should be correctly scoped by current tenant' do
    before do
      @account = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = @account.id
      @project = Project.create!(:name => 'foobar', :account_id => @account.id )

      @task1 = Task.create!(:name => 'no_tenant', :project => @project)
      @task1.update_column('account_id', nil)

      @task2 = @project.tasks.create!(:name => 'baz')
      @tasks = @project.tasks
    end

    it 'should correctly set the tenant on the task created with current_tenant set' do
      @task2.account_id.should == @account.id
    end

    it 'should filter out the non-tenant task from the project' do
      @tasks.length.should == 1
    end
  end

  describe 'Associations can only be made with in-scope objects' do
    before do
      @account = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = @account.id+1
      @project1 = Project.create!(:name => 'inaccessible_project')

      Multitenant.current_tenant_id = @account.id
      @project2 = Project.create!(:name => 'accessible_project')
      @task = @project2.tasks.create!(:name => 'bar')
    end

    it do
      @task.update_attributes(:project_id => @project1.id).should be_false
    end

  end

  describe 'Create and save a multitenant child without it having a parent' do
      @account = Account.create!(:name => 'baz')
      Multitenant.current_tenant_id = @account.id

      it {Task.create(:name => 'bar').valid?.should == true}
  end

  describe 'It should be possible to use aliased associations' do
    it { AliasedTask.create(:name => 'foo', :project_alias => @project2).valid?.should == true }
  end

  # Additional default_scopes
  describe 'When dealing with a user defined default_scope' do
    before do
      @account = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = @account.id+1
      @project1 = Project.create!(:name => 'inaccessible')
      @task1 = Task.create!(:name => 'no_tenant', :project => @project1)

      Multitenant.current_tenant_id = @account.id
      @project2 = Project.create!(:name => 'accessible')
      @task2 = @project2.tasks.create!(:name => 'bar')
      @task3 = @project2.tasks.create!(:name => 'baz')
      @task4 = @project2.tasks.create!(:name => 'foo')
      @task5 = @project2.tasks.create!(:name => 'foobar', :completed => true )

      @tasks = Task.all
    end

    it 'should apply both the tenant scope and the user defined default_scope, including :order' do
      @tasks.length.should == 3
      @tasks.should == [@task2, @task3, @task4]
      @tasks = Task.unscoped.all
      @tasks.length.should == 4
    end
  end

  # Validates_uniqueness
  describe 'When using validates_uniqueness_of in a multitenant model' do
    before do
      account = Account.create!(:name => 'foo')
      Multitenant.current_tenant_id = account.id
      Project.create!(:name => 'existing_name')
    end

    it 'should not be possible to create a duplicate within the same tenant' do
      Project.create(:name => 'existing_name').valid?.should == false
    end

    it 'should be possible to create a duplicate outside the tenant scope' do
      account = Account.create!(:name => 'baz')
      Multitenant.current_tenant_id = account.id
      Project.create(:name => 'existing_name').valid?.should == true
    end
  end

  describe 'Handles user defined scopes' do
    before do
      UniqueTask.create!(:name => 'foo', :user_defined_scope => 'unique_scope')
    end

    it { UniqueTask.create(:name => 'foo', :user_defined_scope => 'another_scope').should be_valid }
    it { UniqueTask.create(:name => 'foo', :user_defined_scope => 'unique_scope').should_not be_valid }
  end

  describe 'When using validates_uniqueness_of in a NON-aat model' do
    before do
      UnscopedModel.create!(:name => 'foo')
    end
    it 'should not be possible to create duplicates' do
      UnscopedModel.create(:name => 'foo').valid?.should == false
    end
  end

  # with_tenant_id
  describe "Multitenant.with_tenant_id" do
    it "should set current_tenant to the specified tenant inside the block" do
      @account = Account.create!(:name => 'baz')

      Multitenant.with_tenant_id(@account.id) do
        Multitenant.current_tenant_id.should eq(@account.id)
      end
    end

    it "should reset current_tenant to the previous tenant once exiting the block" do
      @account1 = Account.create!(:name => 'foo')
      @account2 = Account.create!(:name => 'bar')

      Multitenant.current_tenant_id = @account1.id
      Multitenant.with_tenant_id @account2.id do
      end

      Multitenant.current_tenant_id.should eq(@account1.id)
    end

    it "should return the value of the block" do
      @account1 = Account.create!(:name => 'foo')
      @account2 = Account.create!(:name => 'bar')

      Multitenant.current_tenant_id = @account1.id
      Multitenant.with_tenant_id(@account2.id) do
        :foo
      end.should eq :foo
    end

    it "should raise an error when no block is provided" do
      expect { Multitenant.with_tenant_id(1) }.to raise_error(LocalJumpError, /no block given/)
    end
  end

end
