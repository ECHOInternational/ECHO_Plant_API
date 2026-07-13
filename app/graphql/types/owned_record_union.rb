# frozen_string_literal: true

module Types
  # Union of the five independently-owned record types.
  # Used by TransferRecordOwnership to return whichever kind of record was
  # transferred without enumerating separate nullable fields per type.
  class OwnedRecordUnion < Types::BaseUnion
    description 'Any independently-owned record: Plant, Variety, Specimen, Location, or Category.'

    possible_types Types::PlantType,
                   Types::VarietyType,
                   Types::SpecimenType,
                   Types::LocationType,
                   Types::CategoryType

    def self.resolve_type(object, _ctx)
      case object
      when Plant    then Types::PlantType
      when Variety  then Types::VarietyType
      when Specimen then Types::SpecimenType
      when Location then Types::LocationType
      when Category then Types::CategoryType
      end
    end
  end
end
