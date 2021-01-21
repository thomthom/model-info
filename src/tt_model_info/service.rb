require 'sketchup.rb'

module TT::Plugins::ModelInfo

  MODEL_SERVICE = if defined?(Sketchup::ModelService)
    Sketchup::ModelService
  else
    require 'tt_model_info/mock_service'
    MockService
  end

  class ModelInfoService < MODEL_SERVICE

    def initialize
      super('Model Information')
    end

  end

  # TT::Plugins::ModelInfo.service
  def self.service
    @service
  end

  def self.start_service
    unless defined?(Sketchup::ModelService)
      warn 'ModelService not supported by this SketchUp version.'

      # TODO: Debug: Remove later.
      menu = UI.menu('Plugins')
      menu.add_item('Model Info Service') do
        self.start_service_as_tool
      end

      return
    end

    model = Sketchup.active_model
    @service = ModelInfoService.new
    model.services.remove(@service) if @service
    model.services.add(@service)
    @service
  end

  def self.start_service_as_tool
    service = ModelInfoService.new
    model = Sketchup.active_model
    model.select_tool(service)
    service
  end

  unless file_loaded?(__FILE__)
    self.start_service
    file_loaded( __FILE__ )
  end

end
