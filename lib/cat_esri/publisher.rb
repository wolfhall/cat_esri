module CatEsri

  FORMATS = %w(sqlite3 csv cloud elasticsearch)

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
      @skip_upload = options[:skip_upload]
      @elastic_url = options[:elastic_url]

      @cfg_cipher = options[:cfg_cipher]
      @cfg_path = options[:cfg_path]
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

          @output.puts "Wrote #{@vault.size} esri entries.\n\n"
          @logger.info "Wrote #{@vault.size} esri entries." if @logger
          
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

        @output.puts "Wrote #{@vault.size} esri entries.\n\n"
        @logger.info "Wrote #{@vault.size} esri entries." if @logger

      when 'cloud'

        unless File.exists?(@cfg_path)
          @output.puts "Aborting upload, storage config not found: #{@cfg_path}"
          @logger.error "Aborting upload, storage config not found: #{@cfg_path}" if @logger
          return
        end

        cfg = decrypted_inflated_cfg(@cfg_cipher, @cfg_path)

        @output.puts "Writing to: #{outfile}"
        @logger.info "Writing to: #{outfile}" if @logger

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

        encrypted_deflated_csv = deflate_encrypt(cfg['cipher_key'], outfile)

        if @skip_upload

          cryptout = File.join(File.dirname(outfile),File.basename(outfile,'cloud')+'crypt')

          File.open(cryptout, 'w') do |f|
            f.write(encrypted_deflated_csv)
          end

        else

          AWS.config(
            :access_key_id => cfg['access_key'],
            :secret_access_key => cfg['secret_key']
          )
          s3 = AWS::S3.new

          bucket = s3.buckets[cfg['s3_bucket']]
          unless bucket.exists?
            @output.puts "Aborting copy, bucket not found: #{cfg['s3_bucket']}"
            @logger.error "Aborting copy, bucket not found: #{cfg['s3_bucket']}" if @logger
            return
          end

          object = bucket.objects[File.basename(outfile,'.*') + '.crypt']

          5.times do

            object.write(:data => encrypted_deflated_csv, :server_side_encryption => :aes256)

            if object.exists?
              File.delete(outfile) if File.exists?(outfile)
              unless File.exists?(outfile)
                @output.puts "Deleted temp file: #{outfile}"
                @logger.info "Deleted temp file: #{outfile}" if @logger
              end
              break
            end
            sleep 2
          end

          if object.exists?
	    ###############################################
	    # puts "-"*50
	    # raw = object.read
	    # puts inflate_decrypt(cfg['cipher_key'],raw )
	    # puts "-"*50
	    ###############################################
            @output.puts "Wrote #{@vault.size} esri entries to cloud storage.\n\n"
            @logger.info "Wrote #{@vault.size} esri entries to cloud storage." if @logger
          else
            @output.puts "Problem copying file to cloud storage. Kept it here: #{outfile}"
            @logger.error "Problem copying file to cloud storage. Kept it here: #{outfile}" if @logger
          end

        end

      when 'elasticsearch'

        es_url = File.dirname(@elastic_url)
        es_idx = File.basename(@elastic_url)
        Tire.configure{ url es_url }

        docs = @vault.collect{ |h| h.merge!( {:type=>h[:model],:id=>h[:guid]} ) }

        count = 0
        begin
          count += 1

          Tire.index(es_idx) do
            import docs
            refresh
          end

          @output.puts "Wrote #{@vault.size} esri entries.\n\n"
          @logger.info "Wrote #{@vault.size} esri entries." if @logger

        rescue Exception => e
          @output.puts "ElasticSearch bulk import problem: trying again (#{count}).\n\n"
          @logger.info "ElasticSearch bulk import problem: trying again (#{count})" if @logger
          @logger.info e if @logger
          retry if (count < 6)
        end

      end

      @vault.clear

    end

  end

end
