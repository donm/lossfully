begin
  require 'bones'
rescue LoadError
  abort '### Please install the "bones" gem ###'
end

# ensure_in_path 'lib'

task :default => 'test:run'
task 'gem:release' => 'test:run'

Bones do
  name     'lossfully'
  authors  'Don'
  email    'don@ohspite.net'
  url      'FIXME (project homepage)'
  history_file 'CHANGELOG'
  readme_file  'README'
  rdoc.main    'README'
  summary 'Smartly generate transcoded (lossy or not) versions of your main music library.'
  description 'Smartly generate transcoded (lossy or not) versions of your main music library.'

  exclude %w(tmp$ bak$ ~$ CVS \.svn/ \.git/ \.brz/ \.bzrignore ^pkg/ ^coverage/)
  rdoc.include %w(README ^lib/ ^bin/ ^ext/ \.txt$ \.rdoc$)
end

