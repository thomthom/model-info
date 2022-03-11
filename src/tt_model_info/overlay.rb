require 'sketchup.rb'

require 'tt_model_info/constants/view'
require 'tt_model_info/drawing_helper'

module TT::Plugins::ModelInfo

  OVERLAY = if defined?(Sketchup::Overlay)
    Sketchup::Overlay
  else
    require 'tt_model_info/mock_overlay'
    MockOverlay
  end


  class ModelInfoOverlay < OVERLAY

    include DrawingHelper
    include ViewConstants

    attr_reader :overlay_id, :name

    def initialize
      super
      @overlay_id = 'thomthom.modelinfo'.freeze
      @name = 'Model Information'.freeze

      @model_info = {}
      @display_info = false

      @button_points = nil
      @button_hover = false
      @button_pressed = false
    end

    def activate
      super
      update_info(Sketchup.active_model)
    end

    def onMouseMove(flags, x, y, view)
      if @button_points
        pt = Geom::Point3d.new(x, y)
        @button_hover = Geom.point_in_polygon_2D(pt, @button_points, true)
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @button_pressed = @button_hover
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      @button_pressed = false
      purge_all if @button_hover
      view.invalidate
    end


    # @param [Sketchup::View] view
    def start(view)
      puts "start (#{self.class.name})"
      start_observing_app
    end

    # @param [Sketchup::View] view
    def stop(view)
      puts "stop (#{self.class.name})"
      stop_observing_app
      reset(view.model)
    end

    # @param [Sketchup::View] view
    def draw(view)
      draw_frame(view) if @display_info
    end

    # @param [Sketchup::Model] model
    def onOpenModel(model)
      puts "onOpenModel (#{self.class.name})"
      update_info(model)
    end

    # @param [Sketchup::Model] model
    def onNewModel(model)
      puts "onNewModel (#{self.class.name})"
      reset(model)
    end

    def onActiveToolChanged(tools, tool_name, tool_id)
      puts "onActiveToolChanged (#{self.class.name})"
      reset(tools.model)
    end

    def onToolStateChanged(tools, tool_name, tool_id, tool_state)
      puts "onToolStateChanged (#{self.class.name})"
      reset(tools.model)
    end

    # @param [Sketchup::View] view
    def onViewChanged(view)
      @button_points = nil
      view.invalidate
    end

    private

    def reset(model)
      puts "reset (#{self.class.name})"
      @model_info = {}
      @display_info = false

      @button_points = nil
      @button_hover = false
      @button_pressed = false

      model.tools.remove_observer(self)

      model.active_view.invalidate
    end

    def has_unused?
      model = Sketchup.active_model
      model.definitions.any? { |definition|
        definition.count_instances == 0
      }
      # TODO: Count other entities.
    end

    def purge_all
      model = Sketchup.active_model
      model.start_operation('Purge Unused', true)
      model.definitions.purge_unused
      model.layers.purge_unused_layers
      model.layers.purge_unused_folders
      model.materials.purge_unused
      model.styles.purge_unused
      model.commit_operation
      update_info(model)
    end

    BUTTON_HOVER_FILL_COLOR = Sketchup::Color.new(255, 255, 255, 128)
    BUTTON_PRESSED_FILL_COLOR = Sketchup::Color.new(255, 255, 255, 192)

    FRAME_FILL_COLOR = Sketchup::Color.new(64, 64, 64, 128)
    FRAME_STROKE_COLOR = Sketchup::Color.new(255, 255, 255, 255)
    FRAME_TEXT_COLOR = Sketchup::Color.new(255, 255, 255, 255)

    FRAME_DEFAULT_TEXT_OPTIONS = {
      font: "Arial",
      color: FRAME_TEXT_COLOR,
      vertical_align: TextVerticalAlignCapHeight,
    }

    FRAME_PADDING = 15

    # @param [Sketchup::View] view
    def draw_frame(view)
      width = 500
      height = 240
      left = (view.vpwidth / 2) - (width / 2)
      top = 100
      bl = Geom::Point3d.new(left, top + height, 0)
      tr = Geom::Point3d.new(left + width, top, 0)

      view.drawing_color = FRAME_FILL_COLOR
      draw2d_rectangle_filled(view, bl, tr)

      view.line_stipple = STIPPLE_SOLID
      view.drawing_color = FRAME_STROKE_COLOR
      draw2d_rectangle_stroked(view, bl, tr, line_width: 3)

      options = FRAME_DEFAULT_TEXT_OPTIONS
      padding = FRAME_PADDING

      # Title
      pt = Geom::Point3d.new(left + padding, top + padding, 0)
      text = @model_info["Filename"]
      view.draw_text(pt, text, size: 20, bold: true, **options)

      # Location
      text = if @model_info["Geolocation"].empty?
        "Not Geolocated"
      else
        country = @model_info["Geolocation"]["Country"]
        city = @model_info["Geolocation"]["City"]
        location = @model_info["Geolocation"]["Location"]
        "#{country}, #{city} (#{location})"
      end
      pt = Geom::Point3d.new(left + padding, top + padding + 30, 0)
      view.draw_text(pt, text, size: 12, bold: true, **options)

      # Stats
      text = ""
      text << "Faces: #{@model_info["Faces"]} (Triangles: #{@model_info["Triangles"]})\n"
      text << "Edges: #{@model_info["Edges"]}\n"
      text << "Component Definitions: #{@model_info["Component Definitions"]}\n"
      text << "Materials: #{@model_info["Materials"]}\n"
      text << "Styles: #{@model_info["Styles"]}\n"
      text << "Tags: #{@model_info["Tags"]}\n"
      pt = Geom::Point3d.new(left + padding, top + padding + 70, 0)
      draw_stat(view, pt, text)

      # Purge Unused
      pt = Geom::Point3d.new(left + padding + 337, top + padding + 180, 0) # KLUDGE
      draw_button(view, pt, "Purge Unused") if has_unused?
    end

    def draw_stat(view, point, text, size: 12, line_height: 24)
      options = FRAME_DEFAULT_TEXT_OPTIONS
      text.each_line.with_index { |line, i|
        pt = Geom::Point3d.new(point.x, point.y + (line_height * i))
        view.draw_text(pt, line, size: size, bold: true, **options)
      }
    end

    # @param [Sketchup::View] view
    # @param [Geom::Point3d] pt
    # @param [String] text
    def draw_button(view, pt, text)
      options = FRAME_DEFAULT_TEXT_OPTIONS
      bounds = view.text_bounds(pt, text, size: 12, bold: true, **options)

      pad_x = 10
      pad_y = 5
      width = bounds.width + (pad_x + pad_x)
      height = bounds.height + (pad_y + pad_y)

      bl = Geom::Point3d.new(pt.x, pt.y + height, 0)
      tr = Geom::Point3d.new(pt.x + width, pt.y, 0)

      if @button_hover
        color = @button_pressed ? BUTTON_PRESSED_FILL_COLOR : BUTTON_HOVER_FILL_COLOR
        view.drawing_color = color
        draw2d_rectangle_filled(view, bl, tr)
      end
      view.drawing_color = FRAME_STROKE_COLOR
      draw2d_rectangle_stroked(view, bl, tr, line_width: 2)
      @button_points ||= rectangle_fill_points(bl, tr) # KLUDGE

      text_pt = Geom::Point3d.new(pt.x + pad_x, pt.y + pad_y + 3, 0) # KLUDGE!
      view.draw_text(text_pt, text, size: 12, bold: true, **options)
    end


    # @param [Sketchup::Entities] entities
    def collect_info(entities, extended: true)
      # DrawingElement information
      extension = TT::Plugins::ModelInfo
      stats = extension.count_entities(entities, {}, extended)
      info = {}
      TYPE_ORDER.each { |type|
        count = stats[type] || 0
        key = CL_MAP[type]
        info[key] = count
      }
      # Additional model entities information
      model = entities.model
      info["Component Definitions"] = model.definitions.size
      info["Tags"] = model.layers.size
      info["Materials"] = model.materials.size
      info["Styles"] = model.styles.size
      # Model information
      info["Filename"] = File.basename(model.path)
      info["Geolocation"] = {}
      if model.georeferenced?
        lat = model.shadow_info["Latitude"]
        long = model.shadow_info["Longitude"]
        latlong = Geom::LatLong.new(lat, long)
        location = latlong.to_s.match(/LatLong\(([^)]+)\)/).captures[0]
        info["Geolocation"]["Location"] = location
        info["Geolocation"]["Country"] = model.shadow_info["Country"]
        info["Geolocation"]["City"] = model.shadow_info["City"]
        info["Geolocation"]["ShadowTime"] = model.shadow_info["ShadowTime"]
      end
      info
    end

    # @param [Sketchup::Model] model
    def update_info(model)
      puts "update_info (#{self.class.name})"
      @button_points = nil
      @model_info = collect_info(model.entities)
      @display_info = true
      # puts JSON.pretty_generate(@model_info)
      model.tools.remove_observer(self)
      model.tools.add_observer(self)
      model.active_view.invalidate
    end

    def start_observing_app
      # TODO: Need to figure out how model overlays works with Mac's MDI.
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
      Sketchup.add_observer(self)
    end

    def stop_observing_app
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
    end

  end


  # TT::Plugins::ModelInfo.overlay
  def self.overlay
    @overlay
  end

  def self.start_overlay
    unless defined?(Sketchup::Overlay)
      warn 'Overlay not supported by this SketchUp version.'

      # TODO: Debug: Remove later.
      menu = UI.menu('Plugins')
      menu.add_item('Model Info Overlay') do
        self.start_overlay_as_tool
      end

      return
    end

    model = Sketchup.active_model
    @overlay = ModelInfoOverlay.new
    model.overlays.remove(@overlay) if @overlay
    model.overlays.add(@overlay)
    @overlay
  end

  def self.start_overlay_as_tool
    overlay = ModelInfoOverlay.new
    model = Sketchup.active_model
    model.select_tool(overlay)
    overlay
  end

  unless file_loaded?(__FILE__)
    self.start_overlay
    file_loaded( __FILE__ )
  end

end
