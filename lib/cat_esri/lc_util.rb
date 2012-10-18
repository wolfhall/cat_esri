module CatEsri
  # A collection of utility methods

  #----------
  # Construct an MD5 checksum based on all bytes if the file is < CS_MAXMB or
  # on smaller chunks from the head and tail if the file is > CS_MAXMB.
  CS_MAXMB = 25 * 1024**2
  CS_CHUNK = CS_MAXMB * 0.25
  def checksum(path)
    return nil unless File.exist?(path)
    return nil if File.directory?(path)
    begin
      inc_digest = Digest::MD5.new
      cs = "unset"
      b = File.size(path)
      f = File.open(path, 'rb')
      if (b < CS_MAXMB)
        # small enough. read entire file
        inc_digest << f.read
        cs = inc_digest.hexdigest
      elsif (b > CS_MAXMB && b < 2**30)
        # checksum just chunks. one from head, one from tail
        inc_digest << f.read(CS_CHUNK)
        f.pos = b-(CS_CHUNK)
        inc_digest << f.read(CS_CHUNK)
        cs = inc_digest.hexdigest
      elsif (b > 2**30)
        # file is too big for File.pos (which needs a long, not Bignum)
        inc_digest << f.read(CS_MAXMB)
        cs = inc_digest.hexdigest
      end
      f.close
      return cs
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # Just a hostname.
  def hostname
    begin
      Socket.gethostname
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end

  #----------
  # use with Find/prune to avoid getting kicked out of recursion due to
  # inaccessible folders
  def inaccessible_dir?(d)
    begin
      return if File.file?(d)
      begin
	Dir.open(File.join(d,'.'))
      rescue Errno::EACCES
	return true
      rescue Errno::ENOENT
	return true
      end
      return false
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end

  #----------
  # Accept an array of strings (or possibly other arrays) and chop the whole thing
  # down to a cloud of unstructured unique "words" with most troublesome chars and numerics
  # stripped out. This cloud can be used for text search indexes on data types that may not
  # necessarily contain formatted text and have a lot of redundancy (like shapefiles).
  def get_uniq_cloud(a)
    begin
      ucloud = []
      # some golf to yield a single array of unique stings
      a.flatten.uniq.join(' ').scan(/\w+/).uniq.each do |x|
	s = x.strip
	# keep 10 and 14 digit UWIs
	#ucloud << s if s =~ /^\d{10}$|^\d{14}$/
	ucloud << s if s =~ /\d{10}00\d{2}|\d{10}/
	# keep string unless it is a number or too short (<2 chars)
	ucloud << s unless s =~ /[-+]?\d*\.?\d+/ || s.length < 2
      end
      return ucloud.join(' ')
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # Basically like checksum, but accepts a string and doesn't worry about size.
  # Slashes are normalized to prevent unix/windows/ruby slash weirdness.
  def guidify(s)
    begin
      Digest::SHA1.hexdigest(s.downcase.gsub('/','').gsub('\\',''))
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # Ghetto method to get a file's owner
  def file_owner(path)
    begin
      if (RbConfig::CONFIG['target_os'] == 'mingw32')
	path = path.gsub("/","\\")
	a = %x[dir /q "#{path}" | findstr "#{File.basename(path)}"]
	b = a.slice(39,a.length)
	return b.slice(0, b.index(' '))
      else
	return %x[ls -l "#{path}"].split[2]
      end
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
      return nil
    end
  end
    


  #----------
  # Paranoid removal of scary characters and stringification of hash keys for
  # easier digestion into sqlite and csv formats. Preserves numeric formats.
  def scrub_values(h)
    begin
      new_v = ""
      h.each_pair do |k,v|
	next if v.nil?
	if ( (v.is_a? Fixnum) || (v.is_a? Float) )
	  h[k] = v
	  next
	else
	  new_v = v.to_s
	  begin
	    # try UTF-8 first, then Windows
	    cleaned = new_v.dup.force_encoding('UTF-8')
	    cleaned = new_v.encode( 'UTF-8', 'Windows-1252' ) unless cleaned.valid_encoding?
	    new_v = cleaned
	  rescue EncodingError
	    # ...you had your chance, string!
	    new_v.encode!( 'UTF-8', invalid: :replace, undef: :replace )
	  end
	  h[k] = new_v
	end
      end
      h.each_pair{ |k,v| h[k] = rm_evil(v) }
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end

  #----------
  # companion of scrub_values. remove some scary characters relevant to csv/index formats
  def rm_evil(s)
    begin
      return "" if s.nil?
      return s unless s.is_a? String
      evil = %w( ' ` , " | )
      evil.each{|x| s.gsub!(x,"_")}
      return s
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end



  #----------
  # use consistent slashes depending on OS
  def normal_seps(s)
    begin
      sep = '/'
      sep = '\\' if @os == "mingw32"
      return s.gsub('/',sep).gsub('\\',sep)
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # Decrypts a compressed yaml cloud config options file and returns hash
  def decrypted_inflated_cfg(key, path)
    begin
      decipher = OpenSSL::Cipher::AES.new(256, :CBC)
      decipher.decrypt
      decipher.key = key
      decipher.iv = Digest::SHA1.hexdigest(key)
      crypted_cfg = File.binread(path)
      decrypted_deflated = decipher.update(crypted_cfg) + decipher.final
      decrypted_inflated = Zlib::Inflate.inflate(decrypted_deflated)
      return YAML.load(decrypted_inflated)
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end

  #----------
  # Compress and encrypt a file (csv crawler output) and return data/string to be written to S3
  def deflate_encrypt(key, path)
    begin
      deflated = Zlib::Deflate.deflate(File.read(path), Zlib::BEST_COMPRESSION)
      cipher = OpenSSL::Cipher::AES.new(256, :CBC)
      cipher.encrypt
      cipher.key = key
      cipher.iv = Digest::SHA1.hexdigest(key)
      encrypted_deflated = cipher.update(deflated) + cipher.final
      return encrypted_deflated
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end

  #----------
  # Decompress and decrypt data/string from S3
  def inflate_decrypt(key, data)
    begin
      decipher_s3 = OpenSSL::Cipher::AES.new(256, :CBC)
      decipher_s3.decrypt
      decipher_s3.key = key
      decipher_s3.iv = Digest::SHA1.hexdigest(key)
      decrypted_deflated = decipher_s3.update(data) + decipher_s3.final
      decrypted_inflated = Zlib::Inflate.inflate(decrypted_deflated)
      return decrypted_inflated
    rescue Exception => e
      @output.puts "#{e.message} #{e.backtrace.inspect}"
      @logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
    end
  end


  #----------
  # convenience class for dealing with MS Access via ADO on Windows
  # http://rubyonwindows.blogspot.com/2007/06/using-ruby-ado-to-work-with-ms-access.html
  class AccessDb

    attr_accessor :mdb, :connection, :data, :fields

    def initialize(mdb=nil)
      @mdb = mdb
      @connection = nil
      @data = nil
      @fields = nil
    end

    def open
      begin
	connection_string = 'Provider=Microsoft.Jet.OLEDB.4.0;Data Source='
	connection_string << @mdb
	@connection = WIN32OLE.new('ADODB.Connection')
	@connection.Open(connection_string)
      rescue Exception => e
	@output.puts "#{e.message} #{e.backtrace.inspect}"
	@logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
      end
    end

    def query(sql)
      recordset = WIN32OLE.new('ADODB.Recordset')
      recordset.Open(sql, @connection)
      @fields = []
      recordset.Fields.each do |field|
        @fields << field.Name
      end
      begin
        @data = recordset.GetRows.transpose
      rescue
        @data = []
      end
      recordset.Close
    end

    def execute(sql)
      begin
        @connection.Execute(sql)
      rescue Exception => e
	@output.puts "#{e.message} #{e.backtrace.inspect}"
	@logger.error "#{e.message} #{e.backtrace.inspect}" if @logger      
      end
    end

    def close
      @connection.Close
    end

  end


end
