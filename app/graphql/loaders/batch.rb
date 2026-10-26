# frozen_string_literal: true

module Loaders
  # Loads one kind of child record for many parents with one query.
  #
  # A field resolver calls `Loaders::Batch.for(context, key) { |ids| ... }.load(id)`
  # and returns the lazy it gets back. graphql-ruby resolves every lazy of one
  # depth together after the whole level has run, so all the plants of a page
  # join one batch; the block then runs once with every id and returns a Hash
  # of id => value. Ids the block leaves out get `default`.
  #
  # Each batch runs once and is then closed: a load after that starts a new
  # batch. Nothing is cached across batches, so a later mutation field in the
  # same document never reads values loaded before it ran.
  class Batch
    def self.for(context, key, default: nil, &perform)
      loaders = (context[:batch_loaders] ||= {})
      loaders[key] ||= new(default: default, &perform)
    end

    def initialize(default: nil, &perform)
      @default = default
      @perform = perform
      @open = nil
    end

    def load(id)
      @open = Pending.new(@perform, @default) if @open.nil? || @open.done?
      batch = @open
      batch.add(id)
      GraphQL::Execution::Lazy.new { batch.value(id) }
    end

    # One batch of ids, performed on the first value read.
    class Pending
      def initialize(perform, default)
        @perform = perform
        @default = default
        @ids = []
        @result = nil
      end

      def add(id)
        @ids << id
      end

      def done?
        !@result.nil?
      end

      def value(id)
        @result ||= @perform.call(@ids.uniq)
        @result.fetch(id) { @default.dup }
      end
    end
  end
end
