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

      @model_info = {}
    end

    def start(view)
      start_observing_app
      start_observing_model(view.model)
    end

    def stop(view)
      stop_observing_model(view.model)
      stop_observing_app
    end

    def draw(view)
      # ...
    end

    # @param [Sketchup::Model]
    def onNewModel(model)
      start_observing_model(model)
    end

    # @param [Sketchup::Model]
    def onOpenModel(model)
      start_observing_model(model)
    end

    private

    def start_observing_app
      # TODO: Need to figure out how model services works with Mac's MDI.
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
      Sketchup.add_observer(self)
    end

    def stop_observing_app
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
    end

    # @param [Sketchup::Model]
    def start_observing_model(model)
      stop_observing_model(model)
      model.add_observer(self)
      model.shadow_info.add_observer(self)
      analyze
    end

    # @param [Sketchup::Model]
    def stop_observing_model(model)
      model.shadow_info.remove_observer(self)
      model.remove_observer(self)
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
