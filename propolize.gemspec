Gem::Specification.new do |spec|
  spec.name              = "propolize"
  spec.version           = "0.2.1"
  spec.platform          = Gem::Platform::RUBY
  spec.authors           = ["Philip Dorrell"]
  spec.email             = ["http://thinkinghard.com/email.html"]
  spec.homepage          = "https://github.com/pdorrell/propolize"
  spec.summary           = "A specialised Markdown-like markup language for 'propositional' writing"
  spec.description       = "Use to generate HTML pages containing 'propositional writing' from the source code."
  spec.rubyforge_project = spec.name

  spec.required_rubygems_version = ">= 1.3.6"
  
  # If you have runtime dependencies, add them here
  # spec.add_runtime_dependency "other", "~> 1.2"
  
  # If you have development dependencies, add them here
  # spec.add_development_dependency "another", "= 0.9"

  # The list of files to be contained in the gem
  spec.files = Dir['lib/**/*.rb']
  spec.files += ["LICENSE.txt", "Rakefile"]

  spec.executables   = []
  
  spec.require_paths = ['lib']
end
