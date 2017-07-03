class AntiNeoplastic
  include Filter
  
  def initialize(checked)
  end

  def cache_key
    "anti_neoplastics"
  end

  def axis
    :anti_neoplastics
  end

  def resolve
    Set.new DataModel::Drug
      .where(anti_neoplastic: true)
      .joins(:interactions)
      .pluck("interactions.id")
  end
end
