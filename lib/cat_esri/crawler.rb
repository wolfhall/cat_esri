module CatEsri

  #----------
  # Collect metadata from ESRI shapefiles, personal geodatabases (via MS Access) and
  # file geodatabases (via hack). See bin/cat-esri for command line options.
  # See www.esri.com and www.opengeospatial.org for geo standards info
  class Crawler
    include CatEsri

    attr_accessor :os, :options

    #----------
    def initialize(output)
      @output = output
      @os = RbConfig::CONFIG['target_os']
    end


    #----------
    # Process ESRI shapefiles and geodatabases or recurse directories
    def scan
      @logger = Logger.new(@options[:logfile], 2, (10 * 1024**2)) if @options[:logfile]
      @options[:output] = @output
      @options[:logger] = @logger
      @pub = Publisher.new(@options)

      @logger.info "="*60 if @logger
      @logger.info "os: #{@os}  user: #{Etc.getlogin}" if @logger
      @logger.info "options: #{@options.inspect}" if @logger
      @logger.info "="*60 if @logger

      @output.puts '----- LogicalCat ESRI Crawler -----'
      @logger.info '----- LogicalCat ESRI Crawler -----' if @logger

      begin

        if File.file?(@options[:path]) && File.extname(@options[:path]).downcase == ".shp"
          parse_shp(@options[:path])
        elsif File.file?(@options[:path]) && File.extname(@options[:path]).downcase == ".mdb"
          if @os != "mingw32"
            @output.puts "Sorry, ESRI Personal Geodatabase scan only works on Windows."
            @logger.warn "Sorry, ESRI Personal Geodatabase scan only works on Windows." if @logger
          else
            parse_pgdb(@options[:path]) if is_esri_pgdb?(@options[:path])
          end
        elsif File.directory?(@options[:path])
          if is_esri_fgdb?(@options[:path])
            parse_fgdb(@options[:path]) unless @options[:shp_only]
          else
            find_esri
          end
        else
          @output.puts "Invalid crawler path: #{@options[:path]}"
          @logger.warn "Invalid crawler path: #{@options[:path]}" if @logger
        end

        @pub.wrap_it_up

      rescue Exception => e
	@output.puts "#{e.message} #{e.backtrace.inspect}"
	@logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
      ensure
        @logger.close if @logger
      end

    end

  end

end
