require "spec_helper"

SingleCov.covered! uncovered: 2 # Rails version check

class CustomAudit < Audited::DynamoAudit
  def custom_method
    "I'm custom!"
  end
end

class TempModel1 < ::ActiveRecord::Base
  self.table_name = :companies
end

class TempModel2 < ::ActiveRecord::Base
  self.table_name = :companies
end

class Models::ActiveRecord::CustomUser < ::ActiveRecord::Base
end

class Models::ActiveRecord::CustomUserSubclass < Models::ActiveRecord::CustomUser
  audited
end

describe Audited::DynamoAudit do
  let(:user) { Models::ActiveRecord::User.create name: "Testing" }

  describe "audit class" do
    around(:example) do |example|
      original_audit_class = Audited.audit_class

      example.run

      Audited.config { |config| config.audit_class = original_audit_class }
    end

    context "when a custom audit class is configured" do
      it "should be used in place of #{described_class}" do
        Audited.config { |config| config.audit_class = "CustomAudit" }
        TempModel1.audited

        record = TempModel1.create

        audit = record.audits.first
        expect(audit).to be_a CustomAudit
        expect(audit.custom_method).to eq "I'm custom!"
      end
    end

    context "when a custom audit class is not configured" do
      it "should default to #{described_class}" do
        TempModel2.audited

        record = TempModel2.create

        audit = record.audits.first
        expect(audit).to be_a Audited::DynamoAudit
        expect(audit.respond_to?(:custom_method)).to be false
      end
    end
  end

  describe "#audited_changes" do
    let(:audit) { Audited.audit_class.new }

    it "allow indifferent access" do
      audit.audited_changes = {foo: "bar"}
      expect(audit.audited_changes[:foo]).to eq "bar"
      expect(audit.audited_changes["foo"]).to eq "bar"
    end
  end

  describe "#undo" do
    let(:user) { Models::ActiveRecord::User.create(name: "John") }

    it "undos changes" do
      user.update_attribute(:name, "Joe")
      user.audits.last.undo
      user.reload
      expect(user.name).to eq("John")
    end

    it "undos destroy" do
      user.destroy
      user.audits.last.undo
      user = Models::ActiveRecord::User.find_by(name: "John")
      expect(user.name).to eq("John")
    end

    it "undos creation" do
      user # trigger create
      expect { user.audits.last.undo }.to change(Models::ActiveRecord::User, :count).by(-1)
    end

    it "fails when trying to undo unknown" do
      audit = user.audits.last
      audit.action = "oops"
      expect { audit.undo }.to raise_error("invalid action given oops")
    end
  end

  describe "user=" do
    it "should be able to set the user to a model object" do
      subject.user = user
      expect(subject.user).to eq(user)
    end

    it "should be able to set the user to a tableless model" do
      Audited.current_user_attributes = [
        :id,
        :core_company_id,
        :auth_token
      ]
      tableless_user = Models::TablelessModel::User.new(id: 12345, core_company_id: 123, auth_token: 'token')
      subject.user = tableless_user
      expect(subject.user.id).to eq(tableless_user.id)
      expect(subject.user.core_company_id).to eq(tableless_user.core_company_id)
      expect(subject.user.auth_token).to eq(tableless_user.auth_token)
    end

    it "should be able to set the user to nil" do
      subject.user_id = 1
      subject.user_type = "Models::ActiveRecord::User"
      subject.username = "joe"

      subject.user = nil

      expect(subject.user).to be_nil
      expect(subject.user_id).to be_nil
      expect(subject.user_type).to be_nil
      expect(subject.username).to be_nil
    end

    it "should be able to set the user to a string" do
      subject.user = "test"
      expect(subject.user).to eq("test")
    end

    it "should clear model when setting to a string" do
      subject.user = user
      subject.user = "testing"
      expect(subject.user_id).to be_nil
      expect(subject.user_type).to be_nil
    end

    it "should clear the username when setting to a model" do
      subject.username = "test"
      subject.user = user
      expect(subject.username).to be_nil
    end
  end

  describe "revision" do
    it "should recreate attributes" do
      user = Models::ActiveRecord::User.create name: "1"
      5.times { |i| user.update_attribute :name, (i + 2).to_s }

      user.audits.each do |audit|
        expect(audit.revision.name).to eq(audit.version.to_s)
      end
    end

    it "should set protected attributes" do
      u = Models::ActiveRecord::User.create(name: "Brandon")
      u.update_attribute :logins, 1
      u.update_attribute :logins, 2

      audits_arr = u.audits.to_a
      expect(audits_arr[2].revision.logins).to eq(2)
      expect(audits_arr[1].revision.logins).to eq(1)
      expect(audits_arr[0].revision.logins).to eq(0)
    end

    it "should bypass attribute assignment wrappers" do
      u = Models::ActiveRecord::User.create(name: "<Joe>")
      expect(u.audits.first.revision.name).to eq("&lt;Joe&gt;")
    end

    it "should work for deleted records" do
      user = Models::ActiveRecord::User.create name: "1"
      user.destroy
      revision = user.audits.last.revision
      expect(revision.name).to eq(user.name)
      expect(revision).to be_a_new_record
    end
  end

  describe ".assign_revision_attributes" do
    it "dups when frozen" do
      user.freeze
      assigned = Audited::DynamoAudit.assign_revision_attributes(user, name: "Bar")
      expect(assigned.name).to eq "Bar"
    end

    it "ignores unassignable attributes" do
      assigned = Audited::DynamoAudit.assign_revision_attributes(user, oops: "Bar")
      expect(assigned.name).to eq "Testing"
    end
  end

  it "should set the version number on create" do
    user = Models::ActiveRecord::User.create! name: "Set Version Number"
    expect(user.audits.first.version).to eq(1)
    user.update_attribute :name, "Set to 2"
    expect(user.audits.where(action: "create").first.version).to eq(1)
    expect(user.audits.where(action: "update").first.version).to eq(2)
    user.destroy
    expect(Audited::DynamoAudit.where(auditable_type: "Models::ActiveRecord::User", auditable_id: user.id, action: "destroy").last.version).to eq(3)
  end

  it "should set the request uuid on create" do
    ::Audited.store[:current_request_uuid] = SecureRandom.uuid
    user = Models::ActiveRecord::User.create! name: "Set Request UUID"
    expect(user.audits.first.request_uuid).not_to be_blank
  end

  describe "reconstruct_attributes" do
    it "should work with the old way of storing just the new value" do
      audits = Audited::DynamoAudit.reconstruct_attributes([Audited::DynamoAudit.new(audited_changes: {"attribute" => "value"})])
      expect(audits["attribute"]).to eq("value")
    end
  end

  describe "audited_classes" do
    it "should include audited classes" do
      expect(Audited::DynamoAudit.audited_classes).to include(Models::ActiveRecord::User)
    end

    it "should include subclasses" do
      expect(Audited::DynamoAudit.audited_classes).to include(Models::ActiveRecord::CustomUserSubclass)
    end
  end

  describe "new_attributes" do
    it "should return the audited_changes without modification for create" do
      new_attributes = Audited::DynamoAudit.new(audited_changes: {int: 1, array: [1]}, action: :create).new_attributes
      expect(new_attributes).to eq({"int" => 1, "array" => [1]})
    end

    it "should return a hash that contains the after values of each attribute" do
      new_attributes = Audited::DynamoAudit.new(audited_changes: {a: [1, 2], b: [3, 4]}, action: :update).new_attributes
      expect(new_attributes).to eq({"a" => 2, "b" => 4})
    end

    it "should return the audited_changes without modification for destroy" do
      new_attributes = Audited::DynamoAudit.new(audited_changes: {int: 1, array: [1]}, action: :destroy).new_attributes
      expect(new_attributes).to eq({"int" => 1, "array" => [1]})
    end
  end

  describe "old_attributes" do
    it "should return the audited_changes without modification for create" do
      old_attributes = Audited::DynamoAudit.new(audited_changes: {int: 1, array: [1]}, action: :create).new_attributes
      expect(old_attributes).to eq({"int" => 1, "array" => [1]})
    end

    it "should return a hash that contains the before values of each attribute" do
      old_attributes = Audited::DynamoAudit.new(audited_changes: {a: [1, 2], b: [3, 4]}, action: :update).old_attributes
      expect(old_attributes).to eq({"a" => 1, "b" => 3})
    end

    it "should return the audited_changes without modification for destroy" do
      old_attributes = Audited::DynamoAudit.new(audited_changes: {int: 1, array: [1]}, action: :destroy).old_attributes
      expect(old_attributes).to eq({"int" => 1, "array" => [1]})
    end
  end

  describe "as_user" do
    it "should record user objects" do
      Audited::DynamoAudit.as_user(user) do
        company = Models::ActiveRecord::Company.create name: "The auditors"
        company.name = "The Auditors, Inc"
        company.save

        company.audits.each do |audit|
          expect(audit.user).to eq(user)
        end
      end
    end

    it "should support nested as_user" do
      Audited::DynamoAudit.as_user("sidekiq") do
        company = Models::ActiveRecord::Company.create name: "The auditors"
        company.name = "The Auditors, Inc"
        company.save
        expect(company.audits.max_by(&:version).user).to eq("sidekiq")

        Audited::DynamoAudit.as_user(user) do
          company.name = "NEW Auditors, Inc"
          company.save
          expect(company.audits.max_by(&:version).user).to eq(user)
        end

        company.name = "LAST Auditors, Inc"
        company.save
        expect(company.audits.max_by(&:version).user).to eq("sidekiq")
      end
    end

    it "should record usernames" do
      Audited::DynamoAudit.as_user(user.name) do
        company = Models::ActiveRecord::Company.create name: "The auditors"
        company.name = "The Auditors, Inc"
        company.save

        company.audits.each do |audit|
          expect(audit.username).to eq(user.name)
        end
      end
    end

    if ActiveRecord::Base.connection.adapter_name != "SQLite"
      it "should be thread safe" do
        expect(user.save).to eq(true)

        t1 = Thread.new do
          Audited::DynamoAudit.as_user(user) do
            sleep 1
            expect(Models::ActiveRecord::Company.create(name: "The Auditors, Inc").audits.first.user).to eq(user)
          end
        end

        t2 = Thread.new do
          Audited::DynamoAudit.as_user(user.name) do
            expect(Models::ActiveRecord::Company.create(name: "The Competing Auditors, LLC").audits.first.username).to eq(user.name)
            sleep 0.5
          end
        end

        t1.join
        t2.join
      end
    end

    it "should return the value from the yield block" do
      result = Audited::DynamoAudit.as_user("foo") do
        42
      end
      expect(result).to eq(42)
    end

    it "should reset audited_user when the yield block raises an exception" do
      expect {
        Audited::DynamoAudit.as_user("foo") do
          raise StandardError.new("expected")
        end
      }.to raise_exception("expected")
      expect(Audited.store[:audited_user]).to be_nil
    end
  end
end
