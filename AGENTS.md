## Overview

**dynamo-audited** is a Rails audit logging gem that stores audit trails in DynamoDB via the [Dynamoid](https://github.com/Dynamoid/dynamoid) ORM. It's forked from [audited](https://github.com/collectiveidea/audited) v5.7.0 and adapted for DynamoDB-backed storage instead of relational tables.

## Commands

### Testing

```bash
# Run all tests (requires DynamoDB Local on http://localhost:8000 and PostgreSQL)
bundle exec rake spec

# Run a single spec file
bundle exec rspec spec/audited/auditor_spec.rb

# Run a single example by line number
bundle exec rspec spec/audited/auditor_spec.rb:42

# Run tests against a specific Rails version
appraisal rails72 bundle exec rake spec
```

### Linting

```bash
bundle exec standardrb            # check style (uses standard gem)
bundle exec standardrb --fix      # auto-fix style issues
```

### Building

```bash
rake build    # creates pkg/dynamo-audited-*.gem
```

### Multi-version test matrix (Appraisals)

Appraisals cover Rails 5.2, 6.0, 6.1, 7.0, 7.1, 7.2. To install and run:
```bash
appraisal install
appraisal rails72 rake spec
```

## Architecture

### Core flow

```
ActiveRecord model
  → .audited(options)          # AuditedClassMethods mixes in callbacks
  → AuditedInstanceMethods     # audit_create / audit_update / audit_destroy / audit_touch
  → DynamoAudit.create(...)    # Dynamoid document stored in DynamoDB
```

Request context (current user, remote IP, request UUID) is captured by `Audited::Sweeper`, an `around_action` automatically added to `ActionController::Base` and `ActionController::API` via the Railtie. Context is stored in `ActiveSupport::CurrentAttributes` (wrapped by `Audited::Store`).

### Key files

| File | Responsibility |
|------|---------------|
| `lib/audited.rb` | Module config, `Audited::Store` (CurrentAttributes wrapper), global defaults |
| `lib/audited/auditor.rb` | `AuditedClassMethods` (`.audited` macro, enable/disable) + `AuditedInstanceMethods` (callbacks, `revisions`, `revision_at`, `without_auditing`) |
| `lib/audited/dynamo_audit.rb` | Dynamoid model; GSIs for auditable lookup and associated-model lookup; `revision`, `undo`, `ancestors` |
| `lib/audited/sweeper.rb` | Controller `around_action` that populates `Audited::Store` per request |
| `lib/audited/railtie.rb` | Auto-registers Sweeper into Rails controllers |
| `lib/audited/rspec_matchers.rb` | `be_audited` / `have_associated_audits` RSpec DSL |

### DynamoDB table layout

`DynamoAudit` uses:
- Primary key: `id` (hash) + `created_at` (range)
- GSI `auditable_id_version_index`: hash=`auditable_id`, range=`version` — used for per-record audit lookup
- GSI `associated_id_associated_type_index`: hash=`associated_id`, range=`associated_type` — used for `has_associated_audits`

### Configuration (host app)

```ruby
Audited.config do |config|
  config.current_user_method = :current_user       # controller method for user
  config.current_user_attributes = [:id, :email]   # attributes to snapshot from user
  config.ignored_attributes = %w[updated_at]       # globally ignored fields
  config.max_audits = 100                          # prune old audits above this count
  config.audit_class = Audited::DynamoAudit        # override audit model
end
```

### Model usage

```ruby
class Article < ApplicationRecord
  audited only: [:title, :body], redacted: [:secret], max_audits: 50
  has_associated_audits
end
```

### Test infrastructure

Tests use a minimal Rails app at `spec/rails_app/` backed by PostgreSQL (for auditable ActiveRecord models) and DynamoDB Local (`http://localhost:8000`) for audit storage. Test models are defined in `spec/support/active_record/models.rb`. DynamoDB is configured via `spec/rails_app/config/initializers/dynamoid.rb`.
