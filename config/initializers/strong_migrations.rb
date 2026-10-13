# Migrations before this version are treated as safe
StrongMigrations.start_after = 20260629214629

StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# Outdated statistics can hurt performance after an index is added
StrongMigrations.auto_analyze = true
