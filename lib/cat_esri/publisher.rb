module CatEsri

  FORMATS = %w(sqlite3 csv cloud)

  class Publisher
    include CatEsri

    #----------
    def initialize(options)
      @vault = []
      @output = options[:output]
      @outdir = options[:outdir]
      @xitems = options[:xitems]
      @format = options[:format]
      @logger = options[:logger]

      @cloud_bucket_name = options[:cloud_bucket_name]
      @cloud_access_key_id = options[:cloud_access_key_id]
      @cloud_secret_access_key = options[:cloud_secret_access_key]
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
    # Ensure unique file names by using datatype, timestamp (with microseconds) and suffix.
    # Also gets called when xitems limit is reached.
    def autoname(type)
      return unless @outdir
      stamp = sprintf('%.6f',"#{Time.now.to_i}.#{Time.now.usec}".to_f).gsub('.','')
      File.join(@outdir,"#{type.upcase}_#{stamp}.#{@format.downcase}")
    end



    #----------
    # Write .csv or sqlite3 files. Assume everything went okay if outfile exists.
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

      when 'cloud'

        @output.puts "Writing (temporarily) to: #{outfile}"
        @logger.info "Writing (temporarily) to: #{outfile}" if @logger

        CSV.open(outfile, "wb") do |csv|
          csv << @vault[0].keys.to_a
          @vault.each do |r|
            begin
              csv << r.values.to_a
            rescue Exception => e
              @output.puts "csv/cloud parsing error: #{e}"
              @logger.error "csv/cloud parsing error: #{e}" if @logger
            end
          end
        end

        AWS.config(
          :access_key_id => @cloud_access_key_id,
          :secret_access_key => @cloud_secret_access_key
        )
        s3 = AWS::S3.new

        bucket = s3.buckets[@cloud_bucket_name]
        unless bucket.exists?
          @output.puts "Aborting copy, bucket not found: #{@cloud_bucket_name}"
          @logger.error "Aborting copy, bucket not found: #{@cloud_bucket_name}" if @logger
        end

        deflated = Zlib::Deflate.deflate(File.read(outfile), Zlib::BEST_COMPRESSION)
        object = bucket.objects[File.basename(outfile,'.*') + '.gz']

        5.times do
          object.write(
            :data => deflated,
            :server_side_encryption => :aes256
          )
          if object.exists?
            @output.puts "Success: (#{object.public_url}) Deleting temp file..."
            @logger.info "Success: (#{object.public_url}) Deleting temp file..." if @logger
            File.delete(outfile) if File.exists?(outfile)
            unless File.exists?(outfile)
              @output.puts "Deleted: #{outfile}"
              @logger.info "Deleted: #{outfile}" if @logger
            end

            break
          end
          sleep 2
        end

        if object.exists?
	  ###############################################
	  # puts "-"*50
	  # s3_deflated = object.read
	  # inflated = Zlib::Inflate.inflate(s3_deflated)
	  # puts inflated
	  # puts "-"*50
	  # sleep 5
	  ###############################################
          @output.puts "Wrote #{@vault.size} entries to cloud.\n\n"
          @logger.info "Wrote #{@vault.size} entries to cloud." if @logger
        else
          @output.puts "Problem copying file to cloud storage. Kept it here: #{outfile}|.zip"
          @logger.error "Problem copying file to cloud storage. Kept it here: #{outfile}|.zip" if @logger
        end

      end

      @output.puts "Wrote #{@vault.size} entries.\n\n" if File.exists?(outfile)
      @logger.info "Wrote #{@vault.size} entries." if File.exists?(outfile) && @logger
      @vault.clear

    end





  end

end
