# frozen_string_literal: true

# Aligns Plant API visibility with ECHOcommunity's editorial state.
#
# ECHOcommunity decides whether a plant is published (migration decision D-007),
# and its deletions made after the 2020 export are authoritative too (D-014).
# Both are carried in as a status file rather than a live database connection,
# so this application never holds a handle on ECHOcommunity's database (D-029).
#
# Only plants owned by the given organization are touched, and only when their
# visibility actually differs. A plant with no entry in the status file is left
# alone: it exists only in the API, which is legitimate (the 2026-08-07 Acacia
# split, and 107 contributed plants), and silence is not evidence of deletion.
class EcVisibilityAligner
  Result = Struct.new(:changed, :unchanged, :absent, :failed, :changes, :errors,
                      keyword_init: true)

  # ECHOcommunity status -> Plant API visibility.
  TARGET = { 'published' => :public, 'draft' => :draft, 'deleted' => :deleted }.freeze

  def initialize(organization:, statuses:, apply: false)
    @organization = organization
    @statuses = statuses
    @apply = apply
  end

  def align
    result = Result.new(changed: 0, unchanged: 0, absent: 0, failed: 0,
                        changes: [], errors: [])
    scope.find_each { |plant| align_plant(plant, result) }
    result
  end

  private

  def scope
    Plant.unscoped.where(owner_organization_id: @organization.id)
  end

  def align_plant(plant, result)
    status = @statuses[plant.id]
    return result.absent += 1 if status.nil?

    target = TARGET[status]
    return result.unchanged += 1 if unchanged?(plant, target)

    record_change(plant, target, status, result)
    plant.update!(visibility: target) if @apply
  rescue StandardError => e
    record_failure(plant, e, result)
  end

  def record_failure(plant, error, result)
    result.failed += 1
    result.changed -= 1
    result.errors << "#{plant.id}: #{error.class}: #{error.message}"
  end

  def unchanged?(plant, target)
    target.nil? || plant.visibility.to_s == target.to_s
  end

  def record_change(plant, target, status, result)
    result.changes << "#{plant.id} #{plant.scientific_name}: " \
                      "#{plant.visibility} -> #{target} (EC: #{status})"
    result.changed += 1
  end
end
