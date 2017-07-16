class IntrigueApp < Sinatra::Base
  namespace '/v1' do

    get '/:project/entities' do
      @result_count = 100

      params[:search_string] == "" ? @search_string = nil : @search_string = params[:search_string]
      params[:entity_types] == "" ? @entity_types = nil : @entity_types = params[:entity_types]
      params[:inverse] == "on" ? @inverse = true : @inverse = false
      params[:correlate] == "on" ? @correlate = true : @correlate = false
      (params[:page] != "" && params[:page].to_i > 0) ? @page = params[:page].to_i : @page = 1

      selected_entities = Intrigue::Model::Entity.scope_by_project(@project_name).where(:hidden=>false).order(:name)

      ## Filter if we have a type
      selected_entities = selected_entities.where(:type => @entity_types) if @entity_types

      if @search_string
        if @inverse
          selected_entities = selected_entities.exclude(Sequel.|(
            Sequel.ilike(:name, "%#{@search_string}%"),
            Sequel.ilike(:details_raw, "%#{@search_string}%")))
        else
          selected_entities = selected_entities.where(Sequel.|(
            Sequel.ilike(:name, "%#{@search_string}%"),
            Sequel.ilike(:details_raw, "%#{@search_string}%")))
        end
      end

      # Handle entity coorelation
      if @correlate

        # Do the meta-analysis
        meta_entities = selected_entities.map {|x| [x] | x.aliases }

        @entities = []
        meta_entities.each do |me|
          temp = []
          merged = false

          meta_entities.each do |me2|
            if (me&me2).any? #&& !(me-me2).empty?
              temp << (me|me2).flatten
              merged = true
            end
          end

          #handle entities that didn't have any aliases
          temp << me.flatten unless merged

          @entities << temp.flatten.sort_by{|x| x.name }.uniq
        end

        @entities.uniq!
        @entity_count = @entities.count
        erb :'entities/index_meta'

      else # normal flow, uncorrelated

        ## paginate
        @entity_count = selected_entities.count
        @entities = selected_entities.extension(:pagination).paginate(@page,@result_count)
        erb :'entities/index'
      end


    end

  get '/:project/entities.csv' do
    content_type 'text/csv'

    project = Intrigue::Model::Project.first(:name => @project_name)
    export = Intrigue::Model::ExportCsv.create(:project_id => project.id)

    export.generate

  export.contents
  end

   get '/:project/entities/:id' do
     @entity = Intrigue::Model::Entity.scope_by_project(@project_name).first(:id => params[:id])
     return "No such entity in this project" unless @entity

     @task_classes = Intrigue::TaskFactory.list

     erb :'entities/detail'
    end

    get '/:project/entities/:id/delete' do
      entity = Intrigue::Model::Entity.scope_by_project(@project_name).first(:id => params[:id])
      return "No such entity in this project" unless entity
      entity.deleted = true
      entity.save
    true
    end

    get '/:project/entities/:id/delete_children' do
      entity = Intrigue::Model::Entity.scope_by_project(@project_name).first(:id => params[:id])
      return "No such entity in this project" unless entity
      #entity.deleted = true
      #entity.save

      Intrigue::Model::TaskResult.scope_by_project(@project_name).where(:base_entity => entity).each do |t|
        t.entities.each { |e| e.deleted = true; e.save }
      end

    true
    end


  end
end
