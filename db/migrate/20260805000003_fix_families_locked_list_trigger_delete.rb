# frozen_string_literal: true

# Task 1's trigger function returned COALESCE(NEW, OLD) unconditionally.
# In PL/pgSQL, NEW is an unassigned record during a DELETE (and OLD is
# unassigned during an INSERT); merely referencing the unassigned side as an
# argument to COALESCE raises "record ... is not assigned yet" before
# COALESCE can evaluate it. This was never exercised until a genuine
# destroy-inside-Family.importing was attempted (Task 1/2 only tested
# destroy blocked outside importing, which raises before any DELETE reaches
# Postgres). Branching on TG_OP avoids referencing the unassigned side.
class FixFamiliesLockedListTriggerDelete < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION families_reject_list_change() RETURNS trigger AS $$
      BEGIN
        IF current_setting('families.import_mode', true) IS DISTINCT FROM 'on' THEN
          RAISE EXCEPTION
            'families is a locked reference list; % is only permitted during an import',
            TG_OP;
        END IF;
        -- Permitted writes must proceed: returning NULL from a BEFORE row
        -- trigger would silently skip the row instead. NEW is unassigned on
        -- DELETE and OLD is unassigned on INSERT, so branch on TG_OP rather
        -- than referencing both sides via COALESCE.
        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        ELSE
          RETURN NEW;
        END IF;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  # Restores migration 1's original function body via CREATE OR REPLACE,
  # rather than raising IrreversibleMigration. The dev database already holds
  # 4,596 real seeded rows, so `rails db:rollback` must not be a dead end for
  # this migration or for any other migration after it in the same run.
  # Restoring the broken COALESCE(NEW, OLD) body on rollback is deliberate: a
  # rollback must reproduce the state migration 1 alone would have left, not
  # invent a third function body that migration 1's own spec never ran
  # against. The trigger itself is untouched -- only its function body
  # changes -- so no DROP TRIGGER / CREATE TRIGGER round trip is needed here.
  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION families_reject_list_change() RETURNS trigger AS $$
      BEGIN
        IF current_setting('families.import_mode', true) IS DISTINCT FROM 'on' THEN
          RAISE EXCEPTION
            'families is a locked reference list; % is only permitted during an import',
            TG_OP;
        END IF;
        -- Permitted writes must proceed: returning NULL from a BEFORE row
        -- trigger would silently skip the row instead.
        RETURN COALESCE(NEW, OLD);
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end
end
