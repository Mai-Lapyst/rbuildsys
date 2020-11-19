# RBuildSys

[![Gem Version](https://badge.fury.io/rb/rbuildsys.svg)](https://rubygems.org/gems/rbuildsys)

RBuildSys is a build system like cmake, where you write your own scripts
to define how your project needs to be build.

## Getting Started

To getting started you first need to install the gem (or build it from this repo :D)
```
gem install rbuildsys
```

### Name your build-script

Next you create your build-script.
RBuildSys dosn't require a specific name for your script, so you can name it how you want.
It also enabled you to have multiple build-scripts that build different things.
For simplicity, i choose `build.rb` here.

### A simple template

This template should get you started:
```ruby
require "rbuildsys"         # requires the gem
include RBuildSys           # Includes the RBuildSys namespace into the global namespace,
                            #  so we dont need to write 'RBuildSys.' before each function!

# This creates a new project named "myproject". The outputfile is also named after this,
# so choose carefully! The :lang options specifies the language to be used, I use c++ here, but
# c is also available. You can also coose to specify the exact c/c++ version you want to use,
# like: "c++17" (needs to be a string then!).
newProject("myproject", :lang => :cpp) do
    useLib("mylib", "/my/path/to/lib")      # adds -lmylib and -L=/my/path/to/lib to the compiler flags!
    flag("-DUSE_MYLIB")                     # adds the string to the compiler flags
    noInstall()                             # prevents this project from being installed
    srcDir("src", "other/src")              # adds source directorys
    incDir("inc", "other/inc")              # adds include directorys
end

build()     # start the build process!
```

For more, check out the documentation! You can generate it using yard.
