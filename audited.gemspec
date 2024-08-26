$:.push File.expand_path("../lib", __FILE__)
require "audited/version"

Gem::Specification.new do |gem|
  gem.name = "audited"
  gem.version = Audited::VERSION

  gem.authors = ["Brandon Keepers", "Kenneth Kalmer", "Daniel Morrison", "Brian Ryckbost", "Steve Richert", "Ryan Glover"]
  gem.email = "info@collectiveidea.com"
  gem.description = "Log all changes to your models"
  gem.summary = gem.description
  gem.homepage = "https://github.com/collectiveidea/audited"
  gem.license = "MIT"

  gem.files = `git ls-files`.split($\).reject { |f| f =~ /^(\.gemspec|\.git|\.standard|\.yard|gemfiles|test|spec)/ }

  gem.required_ruby_version = ">= 2.3.0"

  gem.add_dependency "activerecord", ">= 5.2", "< 8.0"
  gem.add_dependency "activesupport", ">= 5.2", "< 8.0"
  gem.add_dependency "dynamoid"

  gem.add_development_dependency "appraisal"
  gem.add_development_dependency "rails", ">= 5.2", "< 8.0"
  gem.add_development_dependency "rspec-rails"
  gem.add_development_dependency "standard"
  gem.add_development_dependency "single_cov"

  gem.add_development_dependency "pg", ">= 0.18", "< 2.0"
  gem.add_development_dependency  "aws-sdk"
end
