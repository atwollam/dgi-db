class InteractionClaimsController < ApplicationController
  def show
    @interaction_claim = InteractionClaimPresenter.new(
      DataModel::InteractionClaim.for_show.find(params[:id]))
  end

  def interaction_search_results
    #byebug
    if params[:search_mode] == 'mixed'
      if !params[:name].nil?
      params[:search_mode] = 'drugs'
      params[:identifiers] = params[:name]
      params[:gene_categories] = DataModel::GeneClaimCategory.all_category_names unless params[:gene_categories]
      params[:sources] = DataModel::Source.potentially_druggable_source_names unless params[:sources]
      params[:source_trust_levels] = DataModel::SourceTrustLevel.all_trust_levels unless params[:source_trust_levels]
      end
      @search_interactions_active = 'active'

      @view_context = view_context
      unpack_locals(params)

      #interpret_search_logic(params)  #turns search input into readable command of type String (located at params[:identifiers]) - matching
      #byebug
      matches = [[],[]]
      match_string = eval(interpret_search_logic(params))  #need to make global? add to params..
      matches[0] += eval(match_string.gsub!(/\](?![\],])/i, '][0]'))
      matches[1] += eval(match_string.gsub!(/\[0]/i, '[1]'))
      term_string = match_string.gsub(/[\&]/i, '|')
      matches[0] += eval(term_string.gsub!(/\[1]/i, '[2]'))
      matches[1] += eval(term_string.gsub!(/\[2]/i, '[3]'))
      #byebug
      search_results = eval(interpret_search_logic(params, 2)).uniq ###*  still needs to give matches
      #byebug
      @search_results = InteractionSearchResultsPresenter.new(search_results, view_context)
      prepare_export
    else
      if !params[:name].nil?
        params[:search_mode] = 'drugs'
        params[:identifiers] = params[:name]
        params[:gene_categories] = DataModel::GeneClaimCategory.all_category_names unless params[:gene_categories]
        params[:sources] = DataModel::Source.potentially_druggable_source_names unless params[:sources]
        params[:source_trust_levels] = DataModel::SourceTrustLevel.all_trust_levels unless params[:source_trust_levels]
      end
      @search_interactions_active = 'active'
      @search_mode = params[:search_mode]
      if @search_mode == 'drugs'
        params[:drugs] = params[:identifiers]
        combine_input_drugs(params)
      elsif @search_mode == 'genes'
        params[:genes] = params[:identifiers]
        combine_input_genes(params)
      else
        if params[:genes]
          combine_input_genes(params)
        elsif params[:drugs]
          combine_input_drugs(params)
        end
      end
      @view_context = view_context
      unpack_locals(params)
      perform_interaction_search
      prepare_export
    end
  end

  def interactions_for_related_genes
    @related_source_gene = params[:genes]
    combine_input_genes(params)
    related_genes = LookupRelatedGenes.find(params[:gene_names])
    if related_genes.empty?
      not_found("Sorry, we don't have any genes related to #{@related_source_gene}")
    end
    params[:gene_names] = related_genes.flat_map(&:gene_gene_interaction_claims)
      .map { |ic| ic.interacting_gene.name }
    perform_interaction_search
    render :interaction_search_results
  end

  private
  def perform_interaction_search
    validate_interaction_request(params)
    search_results = LookupInteractions.find(params)
    @search_results = InteractionSearchResultsPresenter.new(search_results, view_context)
  end


  def logical_interaction_search(term, matches=[], run=1) ###^
    #byebug
    validate_logical_interaction_request(term)
    determine_search_mode(term, params)
    if run == 1  #initial matching run
      LookupInteractions.logical_find(term, params) #should return array of matching drugs to term=gene
    else  #resulting runs
      LookupInteractions.logical_find(term, params, matches, run) #should return full interaction_results; same code as find ?
    end
  end

  def unpack_locals(params)
    @preset_fda = (params[:fda_approved_drug] == "checked" ? "FDA Approved" : "")
    @preset_neo = (params[:anti_neoplastic] == "checked" ? "Anti-neoplastics" : "")
    @preset_immuno = (params[:immunotherapy] == "checked" ? "Immunotherapies" : "")
    @preset_clin = (params[:clinically_actionable] == "checked" ? "Clinically Actionable" : "")
    @preset_druggable = (params[:druggable_genome] == "checked" ? "Druggable Genome" : "")
    @preset_resist = (params[:drug_resistance] == "checked" ? "Drug Resistance" : "")
  end

  def prepare_export(compound_field_separator = '|')
    headers = %w[search_term match_term match_type gene drug interaction_types sources pmids]
    @tsv = CSV.generate(col_sep: "\t") do |tsv|
      tsv << headers
      @search_results.search_results.each do |result|
        match_field = result.type.singularize + '_id'
        row_hash = {
            'match_type' => result.match_type_label,
            'search_term' => result.search_term
        }
        identifiers = result.identifiers
        result.interactions.each do |interaction|
          id = interaction[match_field]
          row_hash['match_term'] = identifiers.select { |i| i.id == id}.first.name
          row_hash['gene'] = interaction.gene.name
          row_hash['drug'] = interaction.drug.name
          row_hash['interaction_types'] = interaction.type_names.join(compound_field_separator)
          row_hash['pmids'] = interaction.pmids.join(compound_field_separator)
          row_hash['sources'] = interaction.source_names.join(compound_field_separator)
          tsv << headers.map{ |field| row_hash[field] }
        end
      end
    end
  end
end
