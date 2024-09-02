# frozen_string_literal: true

require "set"

module Audited
  class DynamoAudit
    include ::Dynamoid::Document

    table name: :audits, key: :id, capacity_mode: :on_demand

    field :auditable_id, :string
    field :auditable_type, :string
    field :associated_id, :string
    field :associated_type, :string
    field :user_id, :string
    field :user_type, :string
    field :username, :string
    field :user_attributes, :map
    field :action, :string
    field :audited_changes, :map
    field :version, :integer
    field :comment, :string
    field :remote_address, :string
    field :request_uuid, :string

    range :created_at, :datetime

    global_secondary_index hash_key: :auditable_id, range_key: :version, projected_attributes: :all, name: "auditable_id_version_index"

    cattr_accessor :audited_class_names
    self.audited_class_names = Set.new

    before_create :set_version_number, :set_request_uuid, :set_remote_address, :set_audit_user

    class << self
      # class methods to replace active record scope and association

      def auditable_finder(auditable_id, auditable_type)
        where(auditable_id: auditable_id, auditable_type: auditable_type)
      end

      # Returns the list of classes that are being audited
      def audited_classes
        audited_class_names.map(&:constantize)
      end

      def as_user(user)
        last_audited_user = ::Audited.store[:audited_user]
        ::Audited.store[:audited_user] = user
        yield
      ensure
        ::Audited.store[:audited_user] = last_audited_user
      end

      def reconstruct_attributes(audits)
        audits.each_with_object({}) do |audit, all|
          all.merge!(audit.new_attributes)
          all[:audit_version] = audit.version
        end
      end

      def assign_revision_attributes(record, attributes)
        attributes.each do |attr, val|
          record = record.dup if record.frozen?

          if record.respond_to?("#{attr}=")
            # convert BigDecimal timestamp to DateTime
            val = Time.at(val.to_i) if attr.end_with?("_at") && val.is_a?(BigDecimal)
            record.attributes.key?(attr.to_s) ?
              record[attr] = val :
              record.send("#{attr}=", val)
          end
        end
        record
      end
    end

    def associated
      return nil unless associated_type.present?

      associated_type.constantize.find(associated_id)
    end

    def auditable
      auditable_type.constantize.find(auditable_id)
    end

    def ancestors
      self.class.auditable_finder(auditable_id, auditable_type).where("version.lte": version).sort_by(&:version)
    end

    # Return an instance of what the object looked like at this revision. If
    # the object has been destroyed, this will be a new record.
    def revision
      clazz = auditable_type.constantize
      (clazz.find_by_id(auditable_id) || clazz.new).tap do |m|
        tmp_ancestors = ancestors
        self.class.assign_revision_attributes(m, self.class.reconstruct_attributes(tmp_ancestors).merge(audit_version: version))
      end
    end

    # Returns a hash of the changed attributes with the new values
    def new_attributes
      (audited_changes || {}).each_with_object({}.with_indifferent_access) do |(attr, values), attrs|
        attrs[attr] = (action == "update") ? values.last : values
      end
    end

    # Returns a hash of the changed attributes with the old values
    def old_attributes
      (audited_changes || {}).each_with_object({}.with_indifferent_access) do |(attr, values), attrs|
        attrs[attr] = (action == "update") ? values.first : values
      end
    end

    # Allows user to undo changes
    def undo
      case action
      when "create"
        # destroys a newly created record
        auditable.destroy!
      when "destroy"
        # creates a new record with the destroyed record attributes
        auditable_type.constantize.create!(audited_changes)
      when "update"
        # changes back attributes
        auditable.update!(audited_changes.transform_values(&:first))
      else
        raise StandardError, "invalid action given #{action}"
      end
    end

    def user
      if user_attributes.present?
        user_type&.constantize&.new(user_attributes)
      else
        user_type&.constantize&.find(user_id) || username
      end
    end

    # Allows user to be set to a string username, an ActiveRecord object or an ActiveModel object
    # @private
    def user=(user)
      # reset all user fields
      self.user_id = nil
      self.user_type = nil
      self.username = nil
      self.user_attributes = nil
      if user.is_a?(::ActiveRecord::Base)
        self.user_id = user.id
        self.user_type = user.class.name
      elsif user.is_a?(::ActiveModel::Model)
        # user is a tableless model
        self.user_id = user.id
        self.user_type = user.class.name
        user_attr = {}
        user.instance_variables.each do |var_name|
          user_attr[var_name.to_s.gsub('@', '')] = user.instance_variable_get(var_name)
        end
        self.user_attributes = user_attr
      else
        self.username = user
      end
    end

    def audited_changes_indifferent
      original_audited_changes.with_indifferent_access
    end
    alias_method :original_audited_changes, :audited_changes
    alias_method :audited_changes, :audited_changes_indifferent

    private

    def set_version_number
      if action == "create"
        self.version = 1
      else
        audit_with_max_version = self.class.auditable_finder(auditable_id, auditable_type)&.sort_by(&:version)&.last
        self.version = (audit_with_max_version&.version || 0) + 1
      end
    end

    def set_audit_user
      self.user ||= ::Audited.store[:audited_user] # from .as_user
      self.user ||= ::Audited.store[:current_user].try!(:call) # from Sweeper
      nil # prevent stopping callback chains
    end

    def set_request_uuid
      self.request_uuid ||= ::Audited.store[:current_request_uuid]
    end

    def set_remote_address
      self.remote_address ||= ::Audited.store[:current_remote_address]
    end
  end
end
