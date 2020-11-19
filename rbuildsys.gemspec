Gem::Specification.new do |s|
    s.name          = 'rbuildsys'
    s.version       = '0.0.1.pre'
    s.date          = '2020-11-06'
    s.summary       = "Scriptable build system, written in ruby"
    s.description   = <<-EOF
        rbuildsys is a build system like cmake,
        where you write your own scripts to define
        how your project needs to be build
    EOF
    s.authors       = ["Mai-Lapyst"]
    s.files         = ["lib/rbuildsys.rb"]
    s.homepage      = 'https://rubygems.org/gems/rbuildsys'
    s.license       = 'GPL-3.0'
    s.metadata      = {
        "source_code_uri" => "https://github.com/Mai-Lapyst/rbuildsys",
        "homepage_uri"    => "https://github.com/Mai-Lapyst/rbuildsys",
        "bug_tracker_uri" => "https://github.com/Mai-Lapyst/rbuildsys/issues",
        "changelog_uri"   => "https://github.com/Mai-Lapyst/rbuildsys/blob/master/CHANGELOG",
    }
end
