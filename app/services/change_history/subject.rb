# frozen_string_literal: true

module ChangeHistory
  # Maps a version's item_type to the ChangeSubject enum value and resolves a
  # human label for child subjects: the common name text, the linked lookup
  # name, the image name. Labels are resolved at query time and degrade to nil
  # when the referenced row no longer exists.
  class Subject
    RECORD = 'record'

    SIMPLE_TYPES = {
      'Plant' => RECORD,
      'Variety' => RECORD,
      'CommonName' => 'common_name',
      'Image' => 'image'
    }.freeze

    JOIN_TYPES = {
      'CategoriesPlant' => { subject: 'category', model: Category, foreign_key: 'category_id' },
      'TolerancesPlant' => { subject: 'tolerance', model: Tolerance, foreign_key: 'tolerance_id' },
      'TolerancesVariety' => { subject: 'tolerance', model: Tolerance, foreign_key: 'tolerance_id' },
      'GrowthHabitsPlant' => { subject: 'growth_habit', model: GrowthHabit, foreign_key: 'growth_habit_id' },
      'GrowthHabitsVariety' => { subject: 'growth_habit', model: GrowthHabit, foreign_key: 'growth_habit_id' },
      'AntinutrientsPlant' => { subject: 'antinutrient', model: Antinutrient, foreign_key: 'antinutrient_id' },
      'AntinutrientsVariety' => { subject: 'antinutrient', model: Antinutrient, foreign_key: 'antinutrient_id' }
    }.freeze

    def initialize(version)
      @version = version
    end

    def subject_type
      JOIN_TYPES.dig(@version.item_type, :subject) ||
        SIMPLE_TYPES.fetch(@version.item_type, RECORD)
    end

    def label
      case subject_type
      when RECORD then nil
      when 'common_name' then changeset_value('name')
      when 'image' then Image.find_by(id: @version.item_id)&.name
      else join_label
      end
    end

    private

    def join_label
      config = JOIN_TYPES[@version.item_type]
      return nil if config.nil?

      linked_id = changeset_value(config[:foreign_key])
      return nil if linked_id.blank?

      config[:model].find_by(id: linked_id)&.name
    end

    # A create records [nil, value] and a destroy records [value, nil], so the
    # last non-nil entry is the value that names the subject in both directions.
    def changeset_value(key)
      changeset = safe_changeset
      return nil if changeset.blank?

      Array(changeset[key]).compact.last
    end

    def safe_changeset
      @version.changeset
    rescue StandardError => e
      Rails.logger.warn("ChangeHistory::Subject skipped version #{@version.id}: #{e.class}")
      nil
    end
  end
end
