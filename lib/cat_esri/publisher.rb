require "logger"
require "sqlite3"
require "csv"

module CatEsri
  
  FORMATS = %w(sqlite3 csv list)
  
  class Publisher
    include CatEsri
    
    #----------
    def initialize(options)
      @vault = []
      @output = options[:output]
      @outfile = options[:outfile]
      @xitems = options[:xitems]
      @format = options[:format]
      @logger = options[:logger]
    end
    
    
    #----------
    # add a map hash to the vault, publish if xitems
    def add_map(x)
      @vault << x
      if @vault.size == @xitems
        publish(autoname('map'),'maps')
        @vault.clear
      end
    end
    
    
    #----------
    # Publish any remaining data (i.e. haven't exceeded xitems) from various arrays.
    def wrap_it_up
      publish(autoname('map'),'maps') if @vault.size > 0
    end
    
    
    #----------
    # Ensure unique file names by appending datatype and timestamp (with microseconds) to 
    # the original outfile parameter. Gets called when xitems limit is reached too.
    def autoname(type)
      return unless @outfile
      ext = File.extname(@outfile)
      orig_base = File.basename(@outfile,ext)
      stamp = sprintf('%.6f',"#{Time.now.to_i}.#{Time.now.usec}".to_f).gsub('.','')
      fname = "#{orig_base}_#{type.upcase}_#{stamp}#{ext}"
      File.join(File.dirname(@outfile),fname)
    end
    
    

    #----------
    # List items to STDOUT (default, locations only) or write .csv or sqlite3 files. Assume
    # everything went okay if outfile exists (removed expensive validation).
    def publish(outfile,table_name)
      
      @output.puts "\nWriting #{@vault.size} #{@format} entries..."
      @logger.info "Writing #{@vault.size} #{@format} entries..." if @logger

      case @format
      when 'sqlite3'
        
        @output.puts "Writing to: #{outfile}"
        @logger.info "Writing to: #{outfile}" if @logger
        
        begin
          db = SQLite3::Database.new(outfile)
          db.execute("create table #{table_name} (#{@vault[0].keys.collect{|x| x.to_s}.join(',')})")
          db.execute("begin transaction")
          @vault.each do |r|
            s = "insert into #{table_name} (#{r.keys.collect{|x|x.to_s}.join(',')}) values (#{r.values.collect{|x| "'#{x}'"}.join(',')})"
            db.execute(s)
          end
          db.execute("commit")
          db.close
        rescue Exception => e
          raise e
        end
                
      when 'csv'
        
        @output.puts "Writing to: #{outfile}"
        @logger.info "Writing to: #{outfile}" if @logger
        
        CSV.open(outfile, "wb") do |csv|
          csv << @vault[0].keys.to_a
          @vault.each do |r|
            begin
              csv << r.values.to_a
            rescue Exception => e
              @output.puts "csv parsing error: #{e}"
              @logger.info "csv parsing error: #{e}" if @logger
            end
          end
        end
                
      when 'list'
        
        @output.puts "\nListing items..."
        @output.puts "-"*79
        @vault.each do |r|
          @output.puts r[:location]
        end
        @output.puts "-"*79
        @output.puts "Total items: #{@vault.size}\n\n"
        
      end
      
      unless @format == 'list'
        @output.puts "Wrote #{@vault.size} entries.\n\n" if File.exists?(outfile)
        @logger.info "Wrote #{@vault.size} entries." if File.exists?(outfile) && @logger
      end
      @vault.clear

    end
    
    
    
    
    
  end
  
end
