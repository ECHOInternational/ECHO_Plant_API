# frozen_string_literal: true

# Gives factory-built owned records the ownership production actually has.
#
# Before S7 the factories set only `owned_by` and `created_by` email strings and
# left owner_organization_id NULL. That modelled a pre-backfill database. It no
# longer exists: the S3 backfill placed every owned record into an organization,
# `rake ownership:verify` passes against production, and S7 puts NOT NULL on the
# three columns. Specs that build unowned records were therefore asserting
# against a state the database cannot be in, and after S7 removed the legacy
# email grant they failed for that reason rather than because authorization
# changed.
#
# The rule here is the backfill's rule, so a spec keeps meaning what it says:
# a record owned by an email belongs to the personal organization of the
# principal with that email. `create(:plant, owned_by: user.email)` therefore
# still means "this user's plant" and still reads back to that user, now through
# the personal organization instead of the email comparison.
#
# Explicitly passed ownership always wins, so specs that place a record in a
# real organization are untouched.
module FactoryOwnership
  module_function

  def stamp!(record)
    owner = principal_for(record.owned_by)
    return if owner.nil?

    record.owner_organization_id  ||= Organization.personal_for!(owner).id
    record.source_organization_id ||= record.owner_organization_id
    creator = principal_for(record.created_by) || owner
    record.created_by_principal_id ||= creator.id
  end

  # Resolution has to prefer the principal the :user factory made for this
  # email, because that is the one whose personal organization ends up in
  # User#readable_organization_ids. Falling back to legacy_for_email covers
  # records owned by an address no spec ever built a user for.
  def principal_for(email)
    return nil if email.blank?

    Principal.find_by(identity_issuer: 'spec', email: email) ||
      Principal.find_by(email: email) ||
      Principal.legacy_for_email(email)
  end
end
