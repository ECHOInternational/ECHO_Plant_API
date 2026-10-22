# frozen_string_literal: true

# One Postgres advisory lock shared by every FPI and publication WRITE task, so
# two of them can never interleave (a sync racing a rollback, a rebaseline
# racing an image import). GitHub's concurrency group is only a second layer:
# it keeps a single pending run per group and silently cancels an older pending
# one, and the waiter gives up while the ECS task keeps running. This lock is
# the real mutual exclusion.
#
#   lock = OpsAdvisoryLock.acquire!('fpi:sync_plants')   # raises Held when taken
#   ...
# ensure
#   lock&.release
#
# The lock lives on its own private database session, opened outside the
# connection pool. That keeps it independent of transactions and of whatever
# the task does with its working connection (and of test-suite connection
# pinning), and the server releases it if the process dies, so a crashed task
# can never wedge the next one.
#
# Read-only tasks (fpi:preflight, publication:report) must NOT take it.
class OpsAdvisoryLock
  # One constant key for the whole write surface (fits a signed bigint).
  KEY = 0x4543_484F_4F50_5301

  # Raised when another session already holds the lock.
  class Held < StandardError; end

  def self.acquire!(task)
    connection = open_connection
    return new(task, connection) if try_lock(connection)

    connection.disconnect!
    raise Held, 'another ops write task is running (the shared ops advisory lock is held); ' \
                "refusing to start #{task}. Wait for it to finish and run this again."
  end

  # A private session built from the app's own database config, outside the
  # connection pool: the lock must belong to a session nothing else reuses.
  def self.open_connection
    config = ActiveRecord::Base.connection_pool.db_config.configuration_hash.symbolize_keys
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(config)
  end
  private_class_method :open_connection

  def self.try_lock(connection)
    connection.select_value("SELECT pg_try_advisory_lock(#{KEY})")
  rescue StandardError
    connection.disconnect!
    raise
  end
  private_class_method :try_lock

  def initialize(task, connection)
    @task = task
    @connection = connection
  end

  def held?
    !@connection.nil?
  end

  def release
    return unless @connection

    @connection.select_value("SELECT pg_advisory_unlock(#{KEY})")
  ensure
    @connection&.disconnect!
    @connection = nil
  end
end
