# frozen_string_literal: true

# Rails 8.0 compat shim for Mobility 1.2.9's ActiveRecord query plugin.
#
# Mobility's Query plugin exposes the +i18n+ scope. In the no-block form
# (+Model.i18n+ / +relation.i18n+) it returns the relation extended with
# Mobility::Plugins::ActiveRecord::Query::QueryExtension, whose +order+,
# +where+, +select/pluck/group+ and +backend_node+ helpers read the relation's
# model through the raw +@klass+ instance variable.
#
# Rails 8.0 renamed that ActiveRecord::Relation instance variable from +@klass+
# to +@model+ (the public +#klass+ reader still works, delegating to +@model+).
# As a result, on Rails 8 the extended relation's +@klass+ reads back nil, so
# QueryExtension#order short-circuits its guard
# (+return super unless @klass.respond_to?(:mobility_attribute?)+) and emits a
# bare +ORDER BY "name"+ against the physical table -- but +name+ is a Mobility
# container attribute stored inside the jsonb +translations+ column, not a real
# column, so PostgreSQL raises +PG::UndefinedColumn: column "name" does not
# exist+. Every collection resolver that sorts or filters on a translated
# attribute via the +.i18n+ scope (categories, tolerances, growth habits,
# antinutrients, image attributes -- the lookup queries) fails identically.
#
# Mobility 1.3.x fixes this ("add Rails 8 support"), but Mobility is held at
# 1.2.9 (1.3.x carries an unrelated container-backend read/write regression that
# breaks the mobility_compat tripwire -- see the Gemfile/application.rb pins), so
# we cannot escape to it on this rung. This shim restores the +@klass+ ivar the
# 1.2.9 QueryExtension expects at the single point the relation is extended
# (Query.build_query, no-block branch), so the plugin routes ordering/filtering
# back through the jsonb container. ActiveRecord::Relation#spawn copies instance
# variables, so every chained relation downstream inherits both +@klass+ and the
# extension -- the entry point is the only place that needs it.
#
# The block form (+Model.i18n { ... }+) is unaffected: it goes through
# Mobility's VirtualRow, which sets its own +@klass+ explicitly.
#
# Remove when Mobility is unheld to a Rails-8-aware release (> 1.3.2) that passes
# spec/models/mobility_compat_spec.rb unchanged.
module MobilityQueryRails8Compat
  def build_query(klass, locale = Mobility.locale, &block)
    result = super
    # Only the no-block branch returns a bare extended relation whose @klass
    # ivar Rails 8 no longer populates. Restore it from the relation's public
    # #klass reader (which delegates to @model). The block branch returns a
    # VirtualRow-built relation that already carries its own @klass.
    if !block && result.is_a?(::ActiveRecord::Relation) &&
       result.instance_variable_get(:@klass).nil?
      result.instance_variable_set(:@klass, result.klass)
    end
    result
  end
end

Mobility::Plugins::ActiveRecord::Query.singleton_class.prepend(MobilityQueryRails8Compat)
