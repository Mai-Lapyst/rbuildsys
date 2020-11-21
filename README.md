# RBuildSys

[![Gem Version](https://badge.fury.io/rb/rbuildsys.svg)](https://rubygems.org/gems/rbuildsys)

RBuildSys is a build system like cmake, where you write your own scripts
to define how your project needs to be build.

## Getting Started

To getting started you first need to install the gem (or build it from this repo :D)
```shell
gem install rbuildsys
```

RBuildSys is cryptographically signed. To be sure the gem you install hasn’t been tampered with, do:
```shell
# Add my cert
gem cert --add <(curl -Ls https://raw.github.com/Mai-Lapyst/rbuildsys/master/certs/maiLapyst.pem)

# Install with high security, which means all dependent gems must be signed and verified
gem install rbuildsys -P HighSecurity
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

declareProjects("myproject")    # Declares one ore multiple projects to RBuildSys. 
                                #  Mainly used in the help text to display wich projects can be build!

parseARGV();                    # Parses the command line arguments!

# This creates a new project named "myproject". The outputfile is also named after this,
# so choose carefully! The :lang options specifies the language to be used, I use c++ here, but
# c is also available. You can also choose to specify the exact c/c++ version you want to use,
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

### Toolchains

Toolchains define what compiler to use and how the flags are that the compiler uses.
For more information about how to define a custom toolchain, read [toolchain-format.md](./toolchain-format.md).

RBuildSys offers 4 builtin toolchains:
    - `gnu` : the gnu compiler (gcc, g++), but for 32 bit
    - `gnu32` : like `gnu`, but for 32 bit
    - `x86_64-mingw32-w64` : mingw32-w64 compiler for win64
    - `i686-mingw32-w64` : mingw32-w64 compiler for win32

RBuildSys also checks `~/.rbuildsys/toolchains` for any custom toolchain and loads it automaticaly!
If you dont want to install your toolchain into your user, you can supply a filepath to the commandline option `--toolchain`!