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

  def down
    raise ActiveRecord::IrreversibleMigration,
          'not reverting to the broken DELETE-branch function'
  end
end
