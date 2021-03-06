# Copyright (C) 2014-2016 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  class Collection
    class View

      # Provides behaviour around an aggregation pipeline on a collection view.
      #
      # @since 2.0.0
      class Aggregation
        extend Forwardable
        include Enumerable
        include Immutable
        include Iterable
        include Explainable
        include Loggable
        include Retryable

        # @return [ View ] view The collection view.
        attr_reader :view
        # @return [ Array<Hash> ] pipeline The aggregation pipeline.
        attr_reader :pipeline

        # Delegate necessary operations to the view.
        def_delegators :view, :collection, :read, :cluster

        # Delegate necessary operations to the collection.
        def_delegators :collection, :database

        # The reroute message.
        #
        # @since 2.1.0
        REROUTE = 'Rerouting the Aggregation operation to the primary server.'.freeze

        # Set to true if disk usage is allowed during the aggregation.
        #
        # @example Set disk usage flag.
        #   aggregation.allow_disk_use(true)
        #
        # @param [ true, false ] value The flag value.
        #
        # @return [ true, false, Aggregation ] The aggregation if a value was
        #   set or the value if used as a getter.
        #
        # @since 2.0.0
        def allow_disk_use(value = nil)
          configure(:allow_disk_use, value)
        end

        # Initialize the aggregation for the provided collection view, pipeline
        # and options.
        #
        # @example Create the new aggregation view.
        #   Aggregation.view.new(view, pipeline)
        #
        # @param [ Collection::View ] view The collection view.
        # @param [ Array<Hash> ] pipeline The pipeline of operations.
        # @param [ Hash ] options The aggregation options.
        #
        # @since 2.0.0
        def initialize(view, pipeline, options = {})
          @view = view
          @pipeline = pipeline.dup
          @options = options.dup
        end

        # Get the explain plan for the aggregation.
        #
        # @example Get the explain plan for the aggregation.
        #   aggregation.explain
        #
        # @return [ Hash ] The explain plan.
        #
        # @since 2.0.0
        def explain
          self.class.new(view, pipeline, options.merge(explain: true)).first
        end

        private

        def aggregate_spec
          Builder::Aggregation.new(pipeline, view, options).specification
        end

        def new(options)
          Aggregation.new(view, pipeline, options)
        end

        def initial_query_op
          Operation::Commands::Aggregate.new(aggregate_spec)
        end

        def valid_server?(server)
          server.standalone? || server.mongos? || server.primary? || secondary_ok?
        end

        def secondary_ok?
          pipeline.none? { |op| op.key?('$out') || op.key?(:$out) }
        end

        def send_initial_query(server)
          unless valid_server?(server)
            log_warn(REROUTE)
            server = cluster.next_primary(false)
          end
          validate_collation!(server)
          initial_query_op.execute(server)
        end

        def validate_collation!(server)
          if (@options[:collation] || @options[Operation::COLLATION]) && !server.features.collation_enabled?
            raise Error::UnsupportedCollation.new
          end
        end
      end
    end
  end
end
