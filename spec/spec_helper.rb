ENV["RAILS_ENV"] = "test"
require "bundler/setup"
require "single_cov"
SingleCov.setup :rspec

if Bundler.definition.dependencies.map(&:name).include?("protected_attributes")
  require "protected_attributes"
end
require "rails_app/config/environment"
require "rspec/rails"
require "audited"
require "audited-rspec"
require "audited_spec_helpers"
require "support/active_record/models"

SPEC_ROOT = Pathname.new(File.expand_path("../", __FILE__))

Dir[SPEC_ROOT.join("support/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.include AuditedSpecHelpers
  config.include ActiveSupport::Testing::TimeHelpers
  config.use_transactional_fixtures = false if Rails.version.start_with?("4.")
  config.use_transactional_tests = false if config.respond_to?(:use_transactional_tests=)

  config.before(:each) do
    # Clear PostgreSQL tables
    ActiveRecord::Base.connection.execute("TRUNCATE users, companies, authors, books RESTART IDENTITY CASCADE")

    # Clear DynamoDB audit records
    Audited::DynamoAudit.all.each(&:delete)
  end
end
