class LookupInteractions

  def self.find(params)
    #find gene results for given search terms. end up with
    #an object of type "InteractionSearchResult" for each
    #search result
    gene_results = LookupGenes.find(
      params[:gene_names],
      :for_search,
      InteractionSearchResult
    )
    #get a filter chain encompassing all the given filters from the search form
    filter = create_filter_from_params(params)
    filter_results(gene_results, filter)

    gene_results
  end

  private
  #for each interaction in each result, remove it from the list of interactions
  #for that result if it doesn't meet the filter
  def self.filter_results(gene_results, filter)
    gene_results.each do |result|
      result.filter_interactions do |interaction|
        filter.include?(interaction.id)
      end
    end
  end

  def self.create_filter_from_params(params)
    filter = FilterChain.new
    #TODO this is currently a hack since we're only supporting one drug type on our form
    if params[:limit_drugs] == 'true' || params[:drug_types]
      params[:drug_types] ||= ['antineoplastic']
      create_drug_type_filter(params, filter)
    end
    create_sources_filter(params, filter)
    create_gene_category_filter(params, filter)
    create_interaction_type_filter(params, filter)
    create_source_trust_level_filter(params, filter)
  end

  def self.create_sources_filter(params, chain)
    construct_filter(chain, params[:interaction_sources], :include_source_db_name)
  end

  def self.create_gene_category_filter(params, chain)
    construct_filter(chain, params[:gene_categories], :include_gene_claim_category_interaction)
  end

  def self.create_interaction_type_filter(params, chain)
    construct_filter(chain, params[:interaction_types], :include_interaction_claim_type)
  end

  def self.create_drug_type_filter(params, chain)
    construct_filter(chain, params[:drug_types], :include_drug_claim_type)
  end

  def self.create_source_trust_level_filter(params, chain)
    construct_filter(chain, params[:source_trust_levels], :include_source_trust_level)
  end

  def self.construct_filter(filter, items, filter_name)
    filter.tap do |f|
      Array(items).each do |item|
        f.send(filter_name, item)
      end
    end
  end
end
