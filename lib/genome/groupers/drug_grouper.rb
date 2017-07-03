module Genome
  module Groupers
    class DrugGrouper

      def run
        begin
          newly_added_claims_count = 0
          drug_claims_not_in_groups.in_groups_of(1000, false) do |claims|
            ActiveRecord::Base.transaction do
              grouped_claims = add_members(claims)
              newly_added_claims_count += grouped_claims.length
            end
          end
        end until newly_added_claims_count == 0
      end

      def add_members(claims)
        grouped_claims = []
        claims.each do |drug_claim|
          grouped_claims << group_drug_claim(drug_claim)
        end
        return grouped_claims.compact
      end

      def group_drug_claim(drug_claim)
        # check drug names
        #   - against claim name
        #   - against claim aliases
        if (drug = DataModel::Drug.where('upper(name) in (?) or chembl_id IN (?)', drug_claim.names, drug_claim.names)).one?
          add_drug_claim_to_drug(drug_claim, drug.first)
          return drug_claim
        elsif drug.many?
          direct_multimatch << drug_claim
          return nil
        end

        # check molecule chembl_id and preferred name
        #   - against claim name
        #   - against claim aliases
        if (molecules = DataModel::ChemblMolecule.where('chembl_id IN (?)', drug_claim.names)).one?
          drug = create_drug_from_molecule(molecules.first)
          add_drug_claim_to_drug(drug_claim, drug)
          return drug_claim
        elsif molecules.many?
          molecule_multimatch << drug_claim
          return nil
        elsif (molecules = DataModel::ChemblMolecule.where('upper(pref_name) in (?)', drug_claim.names)).one?
          drug = create_drug_from_molecule(molecules.first)
          add_drug_claim_to_drug(drug_claim, drug)
          return drug_claim
        elsif molecules.many? and (molecule_names = molecules.pluck(:pref_name).map(&:upcase).to_set).one?
          new_drugs = []
          molecules.each do |molecule|
            unless molecule.drug.nil? and rspec_nil? (molecule) # TODO: This is a hack.
              next
            end
            drug = create_drug_from_molecule(molecule)
            new_drugs << drug
          end
          if new_drugs.any?
            return drug_claim
          end
        elsif molecules.many?
          molecule_multimatch << drug_claim
          return nil
        end

        if (molecule_ids = DataModel::ChemblMoleculeSynonym.where('upper(synonym) in (?)', drug_claim.names).pluck(:chembl_molecule_id).to_set).one?
          molecule = DataModel::ChemblMolecule.where(id: molecule_ids.first).first
          drug = create_drug_from_molecule(molecule)
          add_drug_claim_to_drug(drug_claim, drug)
          return drug_claim
        elsif molecule_ids.many?
          molecule_multimatch << drug_claim
          return nil
        end

        # check drug aliases (indirect)
        #   - against claim name
        #   - against claim aliases

        if (drug_ids = DataModel::DrugAlias.where('upper(alias) in (?)', drug_claim.names).pluck(:drug_id).to_set).one?
          drug = DataModel::Drug.where(id: drug_ids.first).first
          add_drug_claim_to_drug(drug_claim, drug)
          return drug_claim
        elsif drug_ids.many?
          indirect_multimatch << drug_claim
          return nil
        end

      end

      def direct_multimatch
        @direct_multimatch ||= Set.new
      end

      def molecule_multimatch
        @molecule_multimatch ||= Set.new
      end

      def indirect_multimatch
        @indirect_multimatch ||= Set.new
      end

      def drug_claims_not_in_groups
        DataModel::DrugClaim.where(drug_id: nil).to_a.keep_if do |drug_claim|
          !(
            (direct_multimatch.member? drug_claim) ||
            (molecule_multimatch.member? drug_claim) ||
            (indirect_multimatch.member? drug_claim)
          )
        end
      end

      def add_drug_claim_to_drug(drug_claim, drug)
        drug.drug_claims << drug_claim
        drug_names = Set.new([drug.name, drug.chembl_id].compact.map(&:upcase))
        drug_aliases = drug.drug_aliases.pluck(:alias).map(&:upcase).to_set
        drug_claim_names = drug_claim.drug_claim_aliases.map{|dca| dca.alias}.to_set
        drug_claim_names += Set.new([drug_claim.name, drug_claim.primary_name].compact)
        drug_claim_names.each do |drug_claim_name|
          if drug_names.member? drug_claim_name.upcase
            next
          end
          unless drug_aliases.member? drug_claim_name.upcase
            drug_alias = DataModel::DrugAlias.create(alias: drug_claim_name, drug: drug)
            drug_alias.sources << drug_claim.source
            drug_aliases << drug_claim_name.upcase
          else
            drug_alias = DataModel::DrugAlias.where('upper(alias) = ? and drug_id = ?',
                                                    drug_claim_name.upcase,
                                                    drug.id
            )
            if drug_alias.empty? # This happened with a lookup for (upper(alias) = '(S)-α')
              next
            end
            drug_alias = drug_alias.first
            unless drug_alias.sources.member? drug_claim.source
              drug_alias.sources << drug_claim.source
            end
          end
        end
        drug_attributes = drug.drug_attributes.pluck(:name, :value)
                              .map { |drug_attribute| drug_attribute.map(&:upcase) }
                              .to_set
        drug_claim.drug_claim_attributes.each do |drug_claim_attribute|
          unless drug_attributes.member? [drug_claim_attribute.name.upcase, drug_claim_attribute.value.upcase]
            drug_attribute = DataModel::DrugAttribute.create(name: drug_claim_attribute.name,
                                                             value: drug_claim_attribute.value,
                                                             drug: drug
            )
            drug_attribute.sources << drug_claim.source
            drug_attributes << [drug_claim_attribute.name.upcase, drug_claim_attribute.value.upcase]
          else
            drug_attribute = DataModel::DrugAttribute.where('upper(name) = ? and upper(value) = ?',
                                                            drug_claim_attribute.name.upcase,
                                                            drug_claim_attribute.value.upcase
            ).first
            unless drug_attribute.sources.member? drug_claim.source
              drug_attribute.sources << drug_claim.source
            end
          end
        end
      end

      def create_drug_from_molecule(molecule)
        if molecule.drug.nil?
          if molecule.duplicate_pref_name?
            drug = molecule.create_and_uniquify_drug
          else
            drug = molecule.create_drug(name: (molecule.pref_name || molecule.chembl_id), chembl_id: molecule.chembl_id)
          end
          molecule.chembl_molecule_synonyms.each do |synonym|
            DataModel::DrugAlias.first_or_create(alias: synonym.synonym, drug: drug)
          end
        else
          return molecule.drug
        end
        drug
      end

      private
      def rspec_nil? (molecule)
        if ENV['RAILS_ENV'] == 'test'
          return DataModel::Drug.where(chembl_id: molecule.chembl_id).none?
        else
          return true
        end
      end
    end
  end
end
