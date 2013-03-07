class DruggableGeneCategoryPresenter
  include Genome::Extensions

  def initialize (search_results)
    @search_results = search_results
  end

  def display_genes
    @display_genes ||= @search_results.map do |result|
      sources = result.gene_claims
                  .map { |claim| claim.source }
                  .select { |source| source.source_type_id == DataModel::SourceType.POTENTIALLY_DRUGGABLE }
                  .map { |source| source.source_db_name }
                  .uniq
                  .sort_by { |s| CategoryResultSortOrder.sort_value(s) }
      DisplayGene.new(result.long_name, sources, result.name)
    end.sort_by { |display_gene| CategoryResultSortOrder.sort_value(display_gene.sources[0]) }
  end

  private
  class DisplayGene < Struct.new(:gene_name, :sources, :short_name)
    def source_links(context)
      my_sources = sources
      context.instance_exec do
        my_sources.map{ |name| link_to(name, "/sources/#{name}") }.join(", ").html_safe
      end
    end
  end
end
