module CatEsri

  MAP_FIELDS = [:store, :label, :group_hash, :identifier, :location, :scanclient, :crawled_at, :model, :project, :checksum, :chgdate, :bytes, :owner, :created, :geometry, :feature_count, :native_extent, :wkt, :guid, :geojson, :cloud]

  # The gdal executables cannot live in bin (dll conflict with ruby on install)
  # Instead, define them here to run from gem location. The path and GDAL_DATA
  # get defined in the trollop executable.
  # exceeding this number will use a bounding box instead.
  OGRINFO     = File.expand_path('../../../gdal/apps/ogrinfo.exe',__FILE__)
  #GDALSRSINFO = File.expand_path('../../../gdal/apps/gdalsrsinfo.exe',__FILE__)
  OGR2OGR     = File.expand_path('../../../gdal/apps/ogr2ogr.exe',__FILE__)

  #----------
  # Recurse through all sub-directories looking for (by default) just shapefiles or
  # (with esrigdb flag) file and personal geodatabases. Include GeoGraphix GeoAtlas layers
  # too if ggxlayer flag is true.
  def find_esri
    @output.puts "Seeking ESRI metadata: #{@options[:path]}"
    @logger.info "Seeking ESRI metadata: #{@options[:path]}" if @logger
    Find.find(@options[:path]) do |f|
      next unless File.directory?(f)
      Find.prune if prune?(f) if @options[:quell]
      Find.prune if inaccessible_dir?(f)
      begin
        Dir.foreach(f) do |d|
          #matches esri shapefiles
          if /\.shp$/.match(d.downcase) && File.file?(File.join(f,d))
            parse_shp(File.join(f,d))
          end

          #matches File GeoDatabase directories
          if /\.gdb$/.match(d.downcase) && File.directory?(File.join(f,d))
            parse_fgdb(File.join(f,d)) if is_esri_fgdb?(File.join(f,d)) && @options[:esrigdb]
          end

          #matches Personal GeoDatabase files
          if /\.mdb$/.match(d.downcase)  && File.file?(File.join(f,d))
            if @os != "mingw32"
              @output.puts "Sorry, ESRI Personal Geodatabase scan only works on Windows."
              @logger.warn "Sorry, ESRI Personal Geodatabase scan only works on Windows." if @logger
            else
              parse_pgdb(File.join(f,d)) if is_esri_pgdb?(File.join(f,d)) && @options[:esrigdb]
            end
          end

        end
      rescue Exception => e
        @output.puts "#{e.message} #{e.backtrace.inspect}"
        @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger
      end
    end
  end

  #----------
  # Check to see if directory should be skipped (case insensitve)
  def prune?(f)
    @options[:quell].split('?').each do |p|
      f = f.gsub('\\','').gsub('/','')
      p = p.gsub('\\','').gsub('/','').strip
      return true if f.casecmp(p) == 0
    end
    return false
  end

  #----------
  # collect info from an ESRI shapefile. text comes from the dbf and .shp.xml if present
  def parse_shp(path)
    @output.puts "Processing ESRI Shapefile: #{path}"
    @logger.info "Processing ESRI Shapefile: #{path}" if @logger
    begin

      strings = []
      strings << get_dbf_cloud(path)

      h = {}

      h[:store]        = 'shapefile'
      h[:label]        = @options[:label]
      h[:group_hash]   = guidify(@options[:group_name])
      h[:identifier]   = File.basename(path.gsub('\\','/').downcase, '.shp')
      h[:location]     = normal_seps(path)
      h[:scanclient]   = hostname
      h[:crawled_at]   = Time.now.strftime("%Y/%m/%d %H:%M:%S")
      h[:model]        = 'map'
      h[:project]      = 'nonproj'
      h[:checksum]     = get_multi_shp_checksum(path)
      h[:chgdate]      = File.mtime(path).strftime("%Y/%m/%d %H:%M:%S")
      h[:bytes]        = get_multi_shp_bytes(path).to_i
      h[:owner]        = file_owner(path)
      h[:created]      = File.ctime(path).strftime("%Y/%m/%d %H:%M:%S")
      
      h = h.merge(get_gdal_data(path))
      
      h[:guid]         = guidify("#{h[:checksum]} #{h[:label]} #{h[:identifier]} #{h[:model]} #{h[:location]}")

      h[:cloud]        = get_uniq_cloud(strings)

      @pub.add_map scrub_values(h)

    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger
    end

  end


  #----------
  # collect info from an ESRI personal geodatabase (Windows only, since it's MS Access)
  def parse_pgdb(path)
    @output.puts "Processing ESRI Personal Geodatabase: #{path}"
    @logger.info "Processing ESRI Personal Geodatabase: #{path}" if @logger

    begin
      require 'win32ole'
      strings = []
      db = AccessDb.new(path)
      db.open

      wkt = db.query("select SRTEXT from GDB_SpatialRefs;")

      # returns a multi-dim array, one array per table. transpose to get 4 x/y columns
      # from which to collect min/max extents for ALL user tables (in whatever x/y projection units)
      db.query("select ExtentLeft, ExtentRight, ExtentBottom, ExtentTop from GDB_GeomColumns")

      x_min = db.data.transpose[0][0] ||= 0.0
      x_max = db.data.transpose[1][0] ||= 0.0
      y_min = db.data.transpose[2][1] ||= 0.0
      y_max = db.data.transpose[3][1] ||= 0.0

      db.query("select name from GDB_ObjectClasses")
      tables = db.data

      tables.each do |t|
  	strings << t.to_s.strip
  	begin
  	  Timeout::timeout(@options[:timeout]) {
  	    db.query("select * from #{t[0]}")
  	    db.data.each do |row|
  	      row.each { |r| strings << r.to_s.strip }
  	    end
	  }
	rescue Timeout::Error
          @output.puts "Exceeded timeout, partial contents returned: #{File.basename(db)}"
          @logger.info "Exceeded timeout, partial contents returned: #{File.basename(db)}" if @logger
        end
      end

      db.close
      h = {}

      h[:store]         = 'esri_pgdb'
      h[:label]         = @options[:label]
      h[:group_hash]    = guidify(@options[:group_name])
      h[:identifier]    = File.basename(path.gsub('\\','/'))
      h[:location]      = normal_seps(path)
      h[:scanclient]    = hostname
      h[:crawled_at]    = Time.now.strftime("%Y/%m/%d %H:%M:%S")
      h[:model]         = 'map'
      h[:project]       = 'nonproj'
      h[:checksum]      = checksum(path)
      h[:chgdate]       = File.mtime(path).strftime("%Y/%m/%d %H:%M:%S")
      h[:bytes]         = File.size(path).to_i
      h[:owner]         = file_owner(path)
      h[:created]       = File.ctime(path).strftime("%Y/%m/%d %H:%M:%S")
      h[:native_extent] = "(#{x_min},#{y_min}) - (#{x_max},#{y_max})"
      h[:wkt]           = wkt
      
      h[:cloud]      = get_uniq_cloud(strings)

      h[:guid]       = guidify("#{h[:checksum]} #{h[:label]} #{h[:identifier]} #{h[:model]} #{h[:location]}")

      @pub.add_map scrub_values(h)

    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end

  end


  #----------
  # collect info from an ESRI file geodatabase. it's a hack, but better than nothing
  def parse_fgdb(path)
    @output.puts "Processing ESRI File Geodatabase: #{path}"
    @logger.info "Processing ESRI File Geodatabase: #{path}" if @logger

    begin
      strings = []
      tables = []
      mod = Time.at(0)
      bytes = 0

      Find.find(path) do |x|
        bytes += File.size(x) unless File.directory?(x)
        tables << File.basename(x, ".spx") if /.spx$/.match(x)
      end

      tables.uniq.each do |x|
        gdb = "#{path}/#{x}.gdbtablx"
        mod = File.mtime(gdb) if(File.mtime(gdb) > mod)

        tablx_i = 16
        tablx_f = File.open(gdb,"rb")
        tablx_size = File.size(tablx_f)

        count = -1
        while tablx_i <= tablx_size
          tablx_f.pos = tablx_i
          idx = (tablx_f.read(4).unpack('I')).to_s
          count += 1 if idx.to_i > 0
          tablx_i = tablx_i+5
        end

        table_f = File.open("#{path}/#{x}.gdbtable","rb")
        a = ""
        begin
          #note: the timeout applies to each table, not the whole fgdb
          Timeout::timeout(@options[:timeout]) {
            table_f.each_byte do |b|
              case b
              when (1..40)
                a << " "
              when (48..57)
                a << b.chr
              when (65..90)
                a << b.chr
              when 95
                a << "_"
              when (97..122)
                a << b.chr
              end
            end
          }
        rescue Timeout::Error
          @output.puts "Exceeded timeout, partial contents returned: #{File.basename(x)}"
          @logger.warn "Exceeded timeout, partial contents returned: #{File.basename(x)}" if @logger
        end
        table_f.close
        tablx_f.close

        strings = a.scan(/\w+/).uniq.collect{|w| w if (w.length > 6 && w.length < 20)}.compact
      end

      h = {}
      h[:store]      = 'esri_fgdb'
      h[:label]      = @options[:label]
      h[:group_hash] = guidify(@options[:group_name])
      h[:identifier] = File.basename(path.gsub('\\','/'))
      h[:location]   = normal_seps(path)
      h[:project]    = 'nonproj'
      h[:checksum]   = get_fgdb_checksum(path)
      h[:chgdate]    = mod.strftime("%Y/%m/%d %H:%M:%S")
      h[:bytes]      = bytes.to_i
      h[:owner]      = file_owner(path)
      h[:created]    = File.ctime(path).strftime("%Y/%m/%d %H:%M:%S")
      h[:cloud]      = get_uniq_cloud(strings)
      h[:scanclient] = hostname
      h[:model]      = 'map'
      h[:crawled_at] = Time.now.strftime("%Y/%m/%d %H:%M:%S")

      h[:guid]       = guidify("#{h[:checksum]} #{h[:label]} #{h[:identifier]} #{h[:model]} #{h[:location]}")

      @pub.add_map scrub_values(h)

    rescue Errno::EACCES => ea
      @output.puts "#{ea.message} #{ea.backtrace.inspect}"
      @logger.error "#{ea.message} #{ea.backtrace.inspect}" if @logger      
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end

  end


  #-------------------
  # Perform a simple check to see if the specified file looks like an ESRI file geodatabase
  # If the .mdb directory contains any .gdbtable and .gdbtablx, it qualifies.
  def is_esri_fgdb?(path)
    #@client_logger.debug "parser_esri | is_esri_fgdb: #{path}"
    begin
      return false if File.file?(path)
      a = true if Dir.entries(path).collect{|x| File.extname(x).downcase}.include?(".gdbtable")
      b = true if Dir.entries(path).collect{|x| File.extname(x).downcase}.include?(".gdbtablx")
      return true if (a && b)
      false
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # Perform a simple check to see if the specified file looks like an ESRI personal
  # geodatabase If the .mdb contains GDB_SpatialRefs, it qualifies.
  def is_esri_pgdb?(path)
    require 'win32ole'
    return false if File.directory?(path)
    begin
      db = AccessDb.new(path)
      db.open
      db.query("select SRTEXT from GDB_SpatialRefs;")
      return true if db.data
    rescue WIN32OLERuntimeError
      return false
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
    false
  end

  
  #----------
  # use a subset of gdal utilities (plucked from the full install) to collect
  # metadata about the shapefile: geometry, feature count and extents.
  # If there are few enough features, create a geojson representation of them.
  # Otherwise, just create a geojson box based on the extents.
  def get_gdal_data(path)
    begin

      a = %x[\"#{OGRINFO}\" -ro -al \"#{path}\" -fid 0]
      
      geometry = nil
      feature_count = 0
      native_extent = nil

      a.each_line do |x|
	geometry = x.split(':')[1].strip if /^Geometry/.match x rescue nil 
	feature_count = x.split(':')[1].strip.to_i if /^Feature Count/.match x rescue nil
	native_extent = x.split(':')[1].strip if /^Extent/.match x rescue nil
      end

      return {
	:geometry => geometry,
	:feature_count => feature_count,
	:native_extent => native_extent
      }.merge(wkt_and_geojson(path))

    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"   
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  def wkt_and_geojson(path)
    begin
      tmp = File.join(options[:outdir],"shp_#{Time.now.to_f}_tmp.json")
      
      prj = "#{File.join(File.dirname(path),File.basename(path.downcase, ".shp"))}.prj"
      ggxgly = File.join(File.dirname(path), "Layer.gly.xml")
      s_srs = nil
      
      if File.exists?(prj)
	s_srs = "ESRI::"+File.read(prj)
      elsif File.exists?(ggxgly)
	g = File.open(ggxgly)
	doc = Nokogiri::XML(g)
	s_srs = "ESRI::"+doc.xpath("/gly/Layer/Attributes/CoordinateSystem/ESRI").inner_text
	g.close
      elsif s_srs.nil?
        @output.puts "Could not find valid source srs for conversion: #{path}"
        @logger.warn "Could not find valid source srs for conversion: #{path}" if @logger      
	File.delete(tmp) if File.exists?(tmp)
	return {:wkt => "Could not find valid projection WKT for conversion."}
      end

      %x[\"#{OGR2OGR}\" -f GeoJSON \"#{tmp}\" \"#{path}\" -s_srs #{s_srs} -t_srs \"EPSG:4326\" -where \"fid < #{@options[:max_features]}\"]

      if File.size?(tmp)
	return { :geojson => File.read(tmp), :wkt => s_srs }
      else
        @output.puts "Could not parse using gdal tools: #{path}"
        @logger.warn "Could not parse using gdal tools: #{path}" if @logger      
	return { :geojson => nil, :wkt => s_srs }
      end
      
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    ensure
      File.delete(tmp) if File.exists?(tmp)
    end
  end



  #----------
  # construct a multi-file composite checksum based on shapefile components
  # path should be the .shp file itself so that other files in the same dir are skipped
  def get_multi_shp_checksum(path)
    begin
      return nil if ! File.exist?(path)
      base = File.basename(path.downcase, '.shp')
      loc = File.dirname(path)
      merged = ""
      shp = (loc+"/"+base).downcase+".shp"
      dbf = (loc+"/"+base).downcase+".dbf"
      prj = (loc+"/"+base).downcase+".prj"
      xml = (loc+"/"+base).downcase+".shp.xml"
      shx = (loc+"/"+base).downcase+".shx"
      sbn = (loc+"/"+base).downcase+".sbn"
      sbx = (loc+"/"+base).downcase+".sbx"
      merged << checksum(shp) if File.exist?(shp)
      merged << checksum(dbf) if File.exist?(dbf)
      merged << checksum(prj) if File.exist?(prj)
      merged << checksum(xml) if File.exist?(xml)
      merged << checksum(shx) if File.exist?(shx)
      merged << checksum(sbn) if File.exist?(sbn)
      merged << checksum(sbx) if File.exist?(sbx)
      return guidify(merged)
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # construct a multi-file checksum based on file geodatabase tables
  def get_fgdb_checksum(path)
    begin
      return unless File.directory?(path)
      cs = ""
      Dir.foreach(path) do |d|
	cs << checksum(File.join(path,d)) if d =~ /.gdbtablx/
      end
      guidify(cs)
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # add up the sizes of shapefile components and avoid extra recursion.
  # path should be the .shp file itself so that other files in the same dir are skipped
  def get_multi_shp_bytes(path)
    begin
      return nil if ! File.exist?(path)
      base = File.basename(path.downcase, '.shp')
      loc = File.dirname(path)
      total = 0
      shp = (loc+"/"+base).downcase+".shp"
      dbf = (loc+"/"+base).downcase+".dbf"
      prj = (loc+"/"+base).downcase+".prj"
      xml = (loc+"/"+base).downcase+".shp.xml"
      shx = (loc+"/"+base).downcase+".shx"
      sbn = (loc+"/"+base).downcase+".sbn"
      sbx = (loc+"/"+base).downcase+".sbx"
      total += File.size(shp) if File.exist?(shp)
      total += File.size(dbf) if File.exist?(dbf)
      total += File.size(prj) if File.exist?(prj)
      total += File.size(xml) if File.exist?(xml)
      total += File.size(shx) if File.exist?(shx)
      total += File.size(sbn) if File.exist?(sbn)
      total += File.size(sbx) if File.exist?(sbx)
      return total
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # parse text columns from a .dbf file (shapefile) and return unique cloud
  # 7-22-2010: added a timeout and char column limiter, primarily for the huge, mostly
  # numeric .dbfs generated by GeoGraphix isomap layers.
  def get_dbf_cloud(path)
    begin
      dp =File.dirname(path)+"/"+File.basename(path.downcase, '.shp')+".dbf"
      
      return unless File.exists?(dp)
      strings = []
      table = DBF::Table.new(dp)

      c = 0
      char_cols = []
      table.columns.each do |col|
	if col.type == "C"
	  char_cols << c
	  strings << col.name
	end
	c += 1
      end

      #shutdown early to save some time if no char columns
      if char_cols.size == 0
	table.close
	return get_uniq_cloud(strings)
      end

      Timeout::timeout(@options[:timeout]) {
        table.each do |r|
          a = r.to_a
          words = a.values_at(*char_cols) #splat
          words.each { |w| strings << w.to_s.strip }
        end
      }
    rescue Timeout::Error
      table.close
      @output.puts "Exceeded timeout, partial contents returned: #{File.basename(path)}"
      @logger.warn "Exceeded timeout, partial contents returned: #{File.basename(path)}" if @logger
      return get_uniq_cloud(strings)
    rescue Exception => x
      @output.puts "ERROR (malformed shapefile): #{x.message} #{x.backtrace.inspect}"
      @logger.error "ERROR (malformed shapefile): #{x.message} #{x.backtrace.inspect}" if @logger      
    end

    table.close
    return get_uniq_cloud(strings)

  end


end
