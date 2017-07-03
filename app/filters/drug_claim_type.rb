class DrugClaimType
  include Filter

  def initialize(type)
    @type = type.downcase
  end

  def cache_key
    "drug_claim.type.#{@type}"
  end

  def axis
    :drugs
  end

  def resolve
    Set.new DataModel::DrugClaimType
      .where('lower(type) = ?', @type)
      .joins(drug_claims: [interaction_claims: :interaction])
      .pluck('interactions.id')
      .uniq
  end
end
