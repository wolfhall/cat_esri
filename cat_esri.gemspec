# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "cat_esri/version"

Gem::Specification.new do |s|
  s.name        = "cat_esri"
  s.version     = CatEsri::VERSION
  s.authors     = ["R. Bryan Hughes"]
  s.email       = ["rbhughes@logicalcat.com"]
  s.homepage    = "http://logicalcat.com"
  s.summary     = %q{LogicalCat ESRI Crawler}
  s.description = %q{Collect text content and file attributes from ESRI shapefiles and personal geodatabases (and some hacky stuff from file geodatabases if you want)}

  s.rubyforge_project = "cat_esri"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "rspec"
  s.add_runtime_dependency "trollop"
  s.add_runtime_dependency "sqlite3"
  s.add_runtime_dependency "dbf"
  s.add_runtime_dependency "tire"
  s.add_runtime_dependency "aws-sdk"
end
