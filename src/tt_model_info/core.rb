#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Model Info' )

require 'tt_model_info/service'

module TT::Plugins::ModelInfo


  ### CONSTANTS ### ------------------------------------------------------------


  MSG_ERROR = MB_OK #| 272 #TT::MB_ICONSTOP
  MSG_OK = MB_OK #| TT::MB_ICONINFORMATION

  # Map DrawingElement types to symbols
  DE_MAP = {
    'Polyline3d'      => :polyline3d,
    'DimensionLinear' => :dimension,
    'DimensionRadial' => :dimension
    #'DimensionLinear' => :dim_lin,
    #'DimensionRadial' => :dim_rad
  }

  CL_MAP = {
    Sketchup::Edge => 'Edges',
    Sketchup::Face => 'Faces',
    Sketchup::Image => 'Images',
    Sketchup::Group => 'Groups',
    Sketchup::ComponentInstance => 'Component Instances',
    Sketchup::ConstructionPoint => 'Guide Points',
    Sketchup::ConstructionLine => 'Guides',
    Sketchup::SectionPlane => 'Section Planes',
    Sketchup::Text => 'Text',
    :polyline3d => '3d Polylines',
    :dimension => 'Dimensions',
    :triangles => 'Triangles'
  }

  CL_MAP_EX = [
    :triangles
  ]

  TYPE_ORDER = [
    Sketchup::Edge,
    Sketchup::Face,
    :triangles,
    Sketchup::ComponentInstance,
    Sketchup::ConstructionLine,
    Sketchup::ConstructionPoint,
    Sketchup::Group,
    Sketchup::Image,
    :polyline3d,
    Sketchup::SectionPlane,
    :dimension,
    Sketchup::Text
  ]


  ### MODULE VARIABLES ### -----------------------------------------------------

  # Preference
  @settings = TT::Settings.new(PLUGIN_ID)
  @settings[:ray_stop_at_ground, false]
  @settings[:rayspray_number, 32]


  ### MENU & TOOLBARS ### ------------------------------------------------------

  unless file_loaded?( File.basename(__FILE__) )
    m = TT.menu('Plugins').add_submenu('Model Info')
    m.add_item('Statistics to File') {
      self.count_model_entities( true, true ) }
    m.add_item('Statistics to Console') {
      self.count_model_entities( false, true ) }
    m.add_separator
    m.add_item('Component Statistics to File') {
      self.count_component_instances( true ) }
    m.add_item('Component Statistics to Console') {
      self.count_component_instances( false ) }
  end


  ### MAIN SCRIPT ### ----------------------------------------------------------


  # Sums up the statistics of the model and outputs it to a file.
  def self.count_model_entities( to_file = true, extended = false )
    model = Sketchup.active_model
    # Prompt for file (if file)
    if to_file
      filename = UI.savepanel('Save Statistics')
      return if filename.nil?
      #unless File.writable?( filename )
      #  UI.messagebox("Cannot write to file.\n#{filename}", MSG_ERROR)
      #  return
      #end
    end
    # Collect stats
    Sketchup.status_text = 'Counting...'
    t = Time.now
    stats = self.count_entities( model.entities, {}, extended )
    puts "\nModel processed in #{Time.now-t}s\n\n"
    # Compile stats
    title = (model.path.empty?) ? 'Untitled' : File.basename( model.path )
    width = 40
    data = []
    data << ('=' * width)
    data << 'Model Statistics'.center(width)
    data << ('-' * width)
    data << "#{title}".center(width)
    data << ('=' * width)
    types = (extended) ? TYPE_ORDER : TYPE_ORDER - CL_MAP_EX
    types.each { |type|
      count = stats[ type ] || 0
      label = CL_MAP[ type ]
      data << "#{label.ljust(25)}#{count}"
    }
    # (!) Output unknown types (incase future new types?)
    data << "#{'Component Definitions'.ljust(25)}#{model.definitions.length}"
    data << "#{'Layers'.ljust(25)}#{model.layers.length}"
    data << "#{'Materials'.ljust(25)}#{model.materials.length}"
    data << "#{'Styles'.ljust(25)}#{model.styles.size}"
    data << ('=' * width)
    # Output data
    if to_file
      begin
        File.open( filename, 'w' ) { |file|
          data.each { |line| file.puts line }
        }
        UI.messagebox("Statistics written to #{filename}", MSG_OK)
      rescue => e
        UI.messagebox("Could not succesfully write to file.\n\n#{e.message}", MSG_ERROR)
        raise e
      end
    else
      # Ensure the Ruby Console is open before the data is output.
      # The timer is required in order to allow the window to open.
      # Without the timer there will be nothing output if the window
      # was not open.
      show_ruby_panel()
      UI.start_timer( 0, false ) { puts data.join("\n") }
    end
  end

  def self.count_entities(entities, table={}, extended = false )
    for e in entities
      c = e.class
      # Account for DrawingElements
      if c == Sketchup::Drawingelement
        type = e.typename
        key = ( DE_MAP.key?( type ) ) ? DE_MAP[ type ] : type.intern
      else
        key = c
      end
      # Update stats
      table[key] ||= 0
      table[key] += 1
      # Count sub-entities
      if c == Sketchup::Group
        self.count_entities( e.entities, table, extended )
      elsif c == Sketchup::ComponentInstance
        self.count_entities( e.definition.entities, table, extended )
      end
      if extended
        if c == Sketchup::Face
          table[:triangles] ||= 0
          table[:triangles] += e.mesh(0).count_polygons
        end
      end # extended
    end
    table
  end


    # Sums up the statistics of the components and outputs it to a file.
  def self.count_component_instances( to_file = true )
    model = Sketchup.active_model
    # Prompt for file (if file)
    if to_file
      filename = UI.savepanel('Save Statistics')
      return if filename.nil?
      #unless File.writable?( filename )
      #  UI.messagebox("Cannot write to file.\n#{filename}", MSG_ERROR)
      #  return
      #end
    end
    # Collect stats
    Sketchup.status_text = 'Counting...'
    t = Time.now
    stats = self.count_components( model.entities )
    puts "\nModel processed in #{Time.now-t}s\n\n"
    # Compile stats
    title = (model.path.empty?) ? 'Untitled' : File.basename( model.path )
    # Find largest string length (!) Count Unicode chars
    #string_length = stats.keys.max { |a,b| a.name.length <=> b.name.length }
    string_length = stats.keys.max { |a,b| a.name.unpack('U*').length <=> b.name.unpack('U*').length }
    string_length = string_length.name.unpack('U*').length + 5
    width = string_length + 10
    data = []
    data << ('=' * width)
    data << 'Component Statistics'.center(width)
    data << ('-' * width)
    data << "#{title}".center(width)
    data << ('=' * width)
    #types = (extended) ? TYPE_ORDER : TYPE_ORDER - CL_MAP_EX
    #names = stats.key.map { |d| d.name }.
    # ASCII sort the definition names - not accurate, but...
    sorted = stats.keys.sort { |a,b| a.name <=> b.name }
    sorted.each { |d|
      # Unicode pad the strings
      strlen = d.name.unpack('U*').length
      buffer = string_length - strlen
      comp_name = d.name + (' ' * buffer)
      data << "#{comp_name}#{stats[d]}"
      #data << "#{d.name.ljust(string_length)}#{stats[d]}"
    }
    data << ('=' * width)
    # Output data
    if to_file
      begin
        File.open( filename, 'w' ) { |file|
          data.each { |line| file.puts line }
        }
        UI.messagebox("Statistics written to #{filename}", MSG_OK)
      rescue => e
        UI.messagebox("Could not succesfully write to file.\n\n#{e.message}", MSG_ERROR)
        raise e
      end
    else
      # Ensure the Ruby Console is open before the data is output.
      # The timer is required in order to allow the window to open.
      # Without the timer there will be nothing output if the window
      # was not open.
      show_ruby_panel()
      UI.start_timer( 0, false ) { puts data.join("\n") }
    end
  end

  def self.count_components(entities, table={} )
    for e in entities
      if e.is_a?( Sketchup::ComponentInstance )
        key = e.definition
        # Update stats
        table[key] ||= 0
        table[key] += 1
      end
      # Count sub-entities
      if e.is_a?( Sketchup::Group )
        self.count_components( e.entities, table )
      elsif e.is_a?( Sketchup::ComponentInstance )
        self.count_components( e.definition.entities, table )
      end
    end
    table
  end


  ### DEBUG ### ----------------------------------------------------------------

  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::ModelInfo.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module

end # if TT_Lib

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------
