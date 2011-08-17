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
  # summary ''
  # description ''

  exclude %w(tmp$ bak$ ~$ CVS \.svn/ \.git/ \.brz/ \.bzrignore ^pkg/)
  rdoc.include %w(README ^lib/ ^bin/ ^ext/ \.txt$ \.rdoc$)

#  gem.extras[:post_install_message] = <<-MSG
# -------
# -------
# MSG
end

