class FileAssetsController < ApplicationController
  
  include Hydra::AssetsControllerHelper
  include Hydra::FileAssetsHelper  
  include Hydra::RepositoryController  
  include MediaShelf::ActiveFedoraHelper
  include Blacklight::SolrHelper
  
  before_filter :require_fedora
  before_filter :require_solr, :only=>[:index, :create, :show, :destroy]
  
  
  def index
=begin
Removed from file_assets/index.html.haml
-# javascript_includes << infusion_javascripts(:inline_edit, :extras=>[:inline_editor_integrations], :debug=>true, :render_html=>false) 
-# javascript_includes << ['../infusion/framework/core/js/ProgressiveEnhancement.js', '../infusion/InfusionAll.js', {:cache=>true, :plugin=>"fluid-infusion"}]

- javascript_includes << "jquery.jeditable.mini"
- javascript_includes << 'custom'
- javascript_includes << "catalog/edit"
- javascript_includes << "jquery.hydraMetadata.js"  
- javascript_includes << "/plugin_assets/fluid-infusion/infusion/components/undo/js/Undo.js" 
- javascript_includes << "jquery.form.js"




=end

    if params[:layout] == "false"
      # action = "index_embedded"
      layout = false
    end
    if !params[:container_id].nil?
      container_uri = "info:fedora/#{params[:container_id]}"
      escaped_uri = container_uri.gsub(/(:)/, '\\:')
      extra_controller_params =  {:q=>"is_part_of_s:#{escaped_uri}"}
      @response, @document_list = get_search_results( extra_controller_params )
      
      # Including this line so permissions tests can be run against the container
      @container_response, @document = get_solr_response_for_doc_id(params[:container_id])
      
      # Including these lines for backwards compatibility (until we can use Rails3 callbacks)
      @container =  ActiveFedora::Base.load_instance(params[:container_id])
      @solr_result = @container.file_objects(:response_format=>:solr)
    else
      # @solr_result = ActiveFedora::SolrService.instance.conn.query('has_model_field:info\:fedora/afmodel\:FileAsset', @search_params)
      @solr_result = FileAsset.find_by_solr(:all)
    end
    render :action=>params[:action], :layout=>layout
  end
  
  def new
=begin
From file_assets/_new.html.haml
=render :partial=>"fluid_infusion/uploader"
=render :partial=>"fluid_infusion/uploader_js"
=end
    render :partial=>"new", :layout=>false
  end
  
  def create
    @file_asset = create_and_save_file_asset_from_params
    apply_depositor_metadata(@file_asset)
        
    if !params[:container_id].nil?
      @container =  ActiveFedora::Base.load_instance(params[:container_id])
      @container.file_objects_append(@file_asset)
      @container.save
    end
    
    ## FOR CAPTURING ANY FILE METADATA // THERE'S PROBABY A BETTER PLACE FOR THIS. 
    unless params[:asset].nil?
      updater_method_args = prep_updater_method_args(params)
      logger.debug("attributes submitted: #{updater_method_args.inspect}")
      result = @file_asset.update_indexed_attributes(updater_method_args[:params], updater_method_args[:opts])
      @file_asset.save
    end
    ##
    
    logger.debug "Created #{@file_asset.pid}."
    render :nothing => true
  end
  
  # Common destroy method for all AssetsControllers 
  def destroy
    # The correct implementation, with garbage collection:
    # if params.has_key?(:container_id)
    #   container = ActiveFedora::Base.load_instance(params[:container_id]) 
    #   container.file_objects_remove(params[:id])
    #   FileAsset.garbage_collect(params[:id])
    # else
    
    # The dirty implementation (leaves relationship in container object, deletes regardless of whether the file object has other containers)
    ActiveFedora::Base.load_instance(params[:id]).delete 
    render :text => "Deleted #{params[:id]} from #{params[:container_id]}."
  end
  
  
  def show
    @file_asset = FileAsset.find(params[:id])
    if (@file_asset.nil?)
      logger.warn("No such file asset: " + params[:id])
      flash[:notice]= "No such file asset."
      redirect_to(:action => 'index', :q => nil , :f => nil)
    else
      # get array of parent (container) objects for this FileAsset
      @id_array = @file_asset.containers(:response_format => :id_array)
      @downloadable = false
      # A FileAsset is downloadable iff the user has read or higher access to a parent
      @id_array.each do |pid|
        @response, @document = get_solr_response_for_doc_id(pid)
        if reader?
          @downloadable = true
          break
        end
      end

      if @downloadable
        if @file_asset.datastreams_in_memory.include?("DS1")
          send_datastream @file_asset.datastreams_in_memory["DS1"]
        end
      else
        flash[:notice]= "You do not have sufficient access privileges to download this document, which has been marked private."
        redirect_to(:action => 'index', :q => nil , :f => nil)
      end
    end
  end
  
end