require "optparse"
require "fileutils"
require "json"

# Namespace for all code for RBuildSys
module RBuildSys

    # Class to describe a buildable RBuildSys project
    #
    # @author Mai-Lapyst
    class Project
        # Returns the name of the project
        # @return [String]
        attr_reader :name

        # Returns the output name of the project; typically the same as {#name}
        # @return [String]
        attr_accessor :outputName

        # Returns the base directory for this project
        # @return [String]
        attr_accessor :baseDir

        # Returns the array of source directorys for this project
        # @return [Array<String>]
        attr_reader :src_dirs

        # Returns the array of source globs for this project
        # @return [Array<String>]
        attr_reader :src_globs

        # Returns the array of include directorys for this project
        # @return [Array<String>]
        attr_reader :inc_dirs

        # Returns the array of "public" include directorys for this project.
        # These will only be used by projects that depends on this project
        # @return [Array<String>]
        attr_reader :public_inc_dirs

        # Returns the array of library directorys for this project
        # @return [Array<String>]
        attr_reader :lib_dirs

        # Returns the array of librarys for this project
        # @return [Array<String>]
        attr_reader :librarys

        # Returns the array of flags for this project; will be added to the compiler call
        # @return [Array<String>]
        attr_reader :flags
        
        # Returns true if the project is install-able, false otherwise
        # @return [true, false]
        attr_accessor :no_install

        # Returns the library type of this project; if nil, this project isn't a library.
        # +:both+ is when the project can be static AND dynamic without any changes inside the sourcecode.
        # @return [:static, :dynamic, :s, :dyn, :both]
        attr_accessor :libType

        # Returns the dependencys of this project
        # @return [Array<Project>]
        attr_reader :dependencys

        # Returns the toolchain used for this project
        # @return [Hash]
        attr_reader :toolchain

        # Returns the defined symbols and its value for this project
        # @return [Hash]
        attr_reader :defines

        # Returns the defined symbols and its value for config files for this project
        # @return [Hash]
        attr_reader :config_symbols

        # Returns the config files that should be configured
        # @return [Array<Hash>]
        attr_reader :config_files

        # Initializes a new instance of this class.
        # Default language is "c".
        #
        # @param name [String] Name of the project; see {#name}
        # @param options [Hash] Various options for the project
        # @option options :lang [Symbol] Language used for this project. Available: +:c+, +:cpp+
        # @option options :toolchain [String] Toolchain that should be used; if no is supplied, "gnu" is used.
        # @option options :srcFile_endings [Array<String>] Additional fileendings that should be used for finding sourcefiles
        # @option options :no_install [true, false] Flag that tells if the project is install-able or not; see {#no_install}
        # @option options :libType [:static, :dynamic, :s, :dyn, :both, nil] Type of library; see {#libType}
        # @option options :outputName [String] If the output name shoud differ from the project name, specify it here
        # @option options :baseDir [String] Directory that should be the base of the project; doesn't change the build directory
        def initialize(name, options = {})
            if (!options.is_a?(Hash)) then
                raise ArgumentError.new("Argument #2 (options) need to be an hash!");
            end

            @name = name;
            @src_dirs = [];
            @src_globs = [];
            @inc_dirs = [];
            @public_inc_dirs = [];
            @lib_dirs = [];
            @dependencys = [];
            @librarys = [];
            @flags = [];
            @defines = {};
            @config_symbols = {};
            @config_files = [];

            check_lang(options[:lang] || "c");
            if (OPTIONS[:toolchainOverride]) then
                if (!load_and_check_toolchain(OPTIONS[:toolchainOverride])) then
                    raise RuntimeError.new("Commandline specified a toolchain override, but toolchain cannot be found: '#{@toolchain_name}'");
                end
            else
                if (!load_and_check_toolchain(options[:toolchain] || "gnu")) then
                    raise ArgumentError.new("Argument #2 (options) contains key toolchain, but toolchain cannot be found: '#{@toolchain_name}'");
                end
            end

            @src_file_endings = [];
            @src_file_endings = ["cpp", "cc", "c++", "cxx"] if (@lang == :cpp);
            @src_file_endings = ["c"] if (@lang == :c);

            if (options[:srcFile_endings]) then
                @src_file_endings.push(*options[:srcFile_endings]);
                @src_file_endings.uniq!;
            end

            @no_install = options[:no_install] || false;
            @libType = options[:libType];
            @outputName = options[:outputName] || @name;
            @baseDir = options[:baseDir] || ".";
        end

        private 
        def load_and_check_toolchain(name)
            @toolchain_name = name;
            @toolchain = TOOLCHAINS[@toolchain_name];
            if (!@toolchain) then
                return false;
            end

            @compiler = @toolchain["compiler"]["c"]   if (@lang == :c);
            @compiler = @toolchain["compiler"]["c++"] if (@lang == :cpp);
            check_binary(@compiler);

            @archiver = @toolchain["archiver"];
            check_binary(@archiver);

            return true;
        end

        private
        def check_binary(bin)
            `which #{bin}`;
            raise RuntimeError.new("Trying to use binary '#{bin}', but binary dosnt exists or is not in PATH") if ($?.exitstatus != 0);
        end

        private
        # lang must be a valid string for the gcc/g++ -std option:
        # https://gcc.gnu.org/onlinedocs/gcc/C-Dialect-Options.html
        # or simply the language: c, c++, gnu, gnu++
        def check_lang(lang)
            if ([:c, :cpp].include?(lang)) then
                @lang = lang;
                return;
            end

            if ((m = lang.match(/^(c\+\+|gnu\+\+)([\dxyza]+)?$/)) != nil) then
                @lang = :cpp;
                @c_standard = lang if (m[2]);
                return;
            end

            if ((m = lang.match(/^(c|gnu)([\dx]+)?$/)) != nil) then
                @lang = :c;
                @c_standard = lang if (m[2]);
                return;
            end

            if (lang.match(/^iso(\d+):([\dx]+)$/) != nil) then
                @lang = :c;
                @c_standard = lang;
                return;
            end

            raise ArgumentError.new("Initializer argument #2 (options) contains key lang, but cannot validate it: '#{lang}'");
        end

        public
        # Cleans the project's output directory
        def clean()
            buildDir = "./build/#{name}";
            FileUtils.remove_dir(buildDir) if File.directory?(buildDir)
        end

        private
        def hasSymbol(sym)
            return true if (@config_symbols.keys.include?(sym));
            return CONFIG_SYMBOLS.keys.include?(sym);
        end

        private
        def getSymbolValue(sym)
            return @config_symbols[sym] if (@config_symbols.keys.include?(sym));
            return CONFIG_SYMBOLS[sym];
        end

        public
        # Configure a specific file
        #
        # @param input [String] The filename of the file that should be configured
        # @param output [String] The filename that should be used to save the result, cannot be the same as the input!
        # @param options [Hash] Some optional options
        # @option options :realUndef [Boolean] If this is true, not defined symbols will be undefined with '#undef <symbol>'
        def configure_file(input, output, options = {})
            # based on https://cmake.org/cmake/help/latest/command/configure_file.html

            puts("- configure: #{input}");

            if (input.is_a?(String)) then
                data = File.read(input);
            end

            # replace cmake defines
            cmake_defines = data.to_enum(:scan, /\#cmakedefine ([a-zA-Z0-9_]+)([^\n]+)?/).map { Regexp.last_match };
            for cmake_def in cmake_defines do
                if (hasSymbol(cmake_def[1])) then
                    data.sub!(cmake_def[0], "#define #{cmake_def[1]}");
                else
                    if (options[:realUndef]) then
                        data.sub!(cmake_def[0], "#undef #{cmake_def[1]}");
                    else
                        data.sub!(cmake_def[0], "/* #undef #{cmake_def[1]} */");
                    end
                end
            end

            # replace variables!
            matches = data.to_enum(:scan, /\@([a-zA-Z0-9_]+)\@/).map { Regexp.last_match };
            for match in matches do
                if (hasSymbol(match[1])) then
                    data.sub!(match[0], getSymbolValue(match[1]).inspect);
                else
                    puts "[WARN] in file #{input}: #{match[0]} found, but no value for it defined!";
                end
            end

            File.write(output, data);
        end

        public
        # Tests if the toolchain for this project is for windows.
        #
        # @return [Boolean] Returns true if windows, false otherwise
        def isWindows?()
            return @toolchain["os"] == "windows";
        end

        public
        # Tests if the toolchain for this project is for macos.
        #
        # @return [Boolean] Returns true if macos, false otherwise
        def isMac?()
            return @toolchain["os"] == "macos";
        end

        public
        # Tests if the toolchain for this project is for linux.
        #
        # @return [Boolean] Returns true if linux, false otherwise
        def isLinux?()
            return @toolchain["os"] == "linux";
        end

        private
        def checkDependencys()
            @dependencys.each_index {|idx|
                dep = @dependencys[idx];
                if (dep.is_a?(Array)) then
                    name = dep[0];

                    # use installed project
                    proj_conf_path = File.join(getInstallPath(), "lib", "rbuildsys_conf", "#{name}.config.json");
                    if (!File.exists?(proj_conf_path)) then
                        raise RuntimeError.new("Could not find project '#{name}'!");
                    end

                    proj_conf = JSON.parse(File.read(proj_conf_path));
                    if (!["static", "dynamic", "both"].include?(proj_conf["libType"])) then
                        raise RuntimeError.new("'#{name}' can't be used as a dependency because it is not a library");
                    end
                    if (proj_conf["libType"] != dep[1].to_s || proj_conf["libType"] == "both") then
                        raise RuntimeError.new("'#{name}' can't be linked with linktype #{dep[1]}");
                    end

                    if (proj_conf["toolchain"] != @toolchain_name) then
                        raise RuntimeError.new("Dependency '#{name}' was compiled using the toolchain #{proj_conf["toolchain"]}, while this project trys to use #{@toolchain_name}!");
                    end

                    @dependencys[idx] = proj_conf;
                end
            }
        end

        public
        # Builds the project
        # @return [true, false] State of the build, true means success, false means failure
        def build()
            for dep in @dependencys do
                next if (OPTIONS[:cleanBuild]);

                if (dep.is_a?(Project) && !dep.build()) then
                    return false;
                end
            end

            puts "Now building '#{@name}'";
            puts "- using language #{@lang}";

            checkDependencys();
            #pp @dependencys.map{|dep| if (dep.is_a?(Project)) then "local #{dep.name}" else "installed #{dep["name"]}" end }

            # TODO: we dont check if previous build files where compiled with the current toolchain or not!

            for config_file in @config_files do
                configure_file(config_file[:input], config_file[:output], config_file[:options]);
            end

            for dep in @dependencys do
                if (dep.is_a?(Project)) then
                    @inc_dirs.push(*dep.public_inc_dirs).uniq!;
                    @lib_dirs.push("./build/#{dep.name}");
                    @librarys.push(dep.name);
                    if (dep.libType == :static) then
                        @lib_dirs.push(*dep.lib_dirs).uniq!
                        @librarys.push(*dep.librarys).uniq!
                    end
                elsif (dep.is_a?(Hash)) then
                    # dependency is an globaly installed library
                    @inc_dirs.push(File.join(getInstallPath(), "include", dep["name"])).uniq!;
                    @lib_dirs.push(File.join(getInstallPath(), "lib")).uniq!;
                    @librarys.push(dep["name"]);
                    if (dep["libType"] == "static") then
                        @lib_dirs.push(*dep["lib_dirs"]).uniq!;
                        @librarys.push(*dep["librarys"]).uniq!;
                    end
                end
            end

            @flags.push(@toolchain["flags"]["debug"]) if (OPTIONS[:debug]);
            @flags.push(@toolchain["extra_flags"]) if (!@toolchain["extra_flags"].strip.empty?);

            # create the project build dir
            buildDir = "./build/#{@name}";
            FileUtils.mkdir_p(buildDir);

            # make the includes
            #inc_dirs.map! { |incDir| incDir + "/*.h" }
            #includes = Dir.glob(inc_dirs);
            includes = @inc_dirs.map{|incDir| "#{@toolchain["flags"]["include"]} #{incDir}"}.join(" ");
            libs = @lib_dirs.map{|libDir| "#{@toolchain["flags"]["libPath"]} #{libDir}"}.join(" ") + " " + @librarys.map{|lib| "#{@toolchain["flags"]["libLink"]} #{lib}"}.join(" ");
            std = @c_standard ? ("#{@toolchain["flags"]["langStd"]}=#{@c_standard}") : "";

            defines = @defines.map{|sym,val|
                if val == nil then
                    "#{@toolchain["flags"]["define"]}#{sym}"
                else
                    "#{@toolchain["flags"]["define"]}#{sym}=#{val}"
                end
            }.join(" ");
            
            # for now, just ignore all global and relative paths for sources
            src_dirs.select! { |srcDir|
                srcDir[0] != "/" && !srcDir.start_with?("../")
            }

            source_modified = false;
            build_failed    = false;

            build_file = ->(srcFile, srcDir) {
                #objFile = File.join(buildDir, srcFile.gsub(srcDir, ""));
                objFile = File.join(buildDir, srcFile);
                objFile = objFile.gsub(Regexp.new("\.(#{@src_file_endings.join("|")})$"), ".o");
                srcTime = File.mtime(srcFile);
    
                if (OPTIONS[:cleanBuild] || OPTIONS[:cleanBuildAll] || !File.exists?(objFile) || (srcTime > File.mtime(objFile))) then
                    source_modified = true;
                    FileUtils.mkdir_p(File.dirname(objFile));   # ensure we have the parent dir(s)
    
                    # build the source!
                    cmd = "#{@compiler}"
                    cmd += " #{std}" if (!std.empty?);
                    cmd += " #{@toolchain["flags"]["pic"]}" if (@libType == :dynamic || @libType == :both);
                    cmd += " #{includes}";
                    cmd += " #{defines}" if (defines.size > 0);
                    cmd += " #{@flags.join(" ")}" if (@flags.size > 0);
                    cmd += " -c #{@toolchain["flags"]["output"]} #{objFile} #{srcFile}";
                    puts "- $ #{cmd}";
                    f = system(cmd);
                    if (f) then
                        FileUtils.touch(objFile, :mtime => srcTime);
                    else
                        build_failed = true;
                    end
                end
            }

            src_dirs.each { |srcDir|
                globStr = File.join(srcDir, "**/*.{#{@src_file_endings.join(",")}}");
                srcFiles = Dir.glob(globStr);
                srcFiles.each { |srcFile|
                    build_file.call(srcFile, srcDir)
                }
            }

            src_globs.each{ |glob|
                srcFiles = Dir.glob(glob);
                srcFiles.each { |srcFile|
                    build_file.call(srcFile, File.dirname(srcFile))
                }
            }

            if (build_failed) then
                puts "Build failed, see log for details!";
                return false;
            end

            objFiles = Dir.glob(buildDir + "/**/*.o");
            if (@libType != nil) then
                f = true;

                if (@libType == :static || @libType == :both) then

                    libname = @toolchain["output_filenames"]["staticLib"].clone;
                    libname.gsub!(/\@[Nn][Aa][Mm][Ee]\@/, @outputName);
                    libpath = File.join(buildDir, libname);

                    if (!File.exists?(libpath) || source_modified) then
                        puts "- Building static library #{libname}!";
                        cmd = "#{@archiver} rcs #{libpath} #{objFiles.join(" ")}";
                        puts "  - $ #{cmd}";
                        f_static = system(cmd);
                        f = false if (!f_static);
                    else
                        puts "- No need for building library, nothing changed!";
                    end
                end

                if (@libType == :dynamic || @libType == :both) then
                    #libname = @toolchain["output_filenames"]["dynamicLib"].clone;
                    #libname.gsub!(/\@[Nn][Aa][Mm][Ee]\@/, @outputName);
                    #puts "- Building dynamic library #{libname}!";
                    #libname = File.join(buildDir, "lib#{name}.so");
                    #cmd = ""
                    puts "[WARN] dynamic librarys are not implemented yet!";
                end

                metadata = {
                    name: @outputName,
                    libType: @libType,
                    lib_dirs: @lib_dirs,
                    librarys: @librarys,
                    dependencys: @dependencys.map {|dep| 
                        if (dep.is_a?(Project)) then
                            dep.outputName
                        else
                            dep["name"];
                        end
                    },
                    toolchain: @toolchain_name
                };
                # TODO: copy the toolchain definition, if the toolchain is not permanently installed on the system!
                metadataFile = File.join(buildDir, "#{@outputName}.config.json");
                File.write(metadataFile, JSON.pretty_generate(metadata));

                return f;
            else
                # build runable binary
                binname = @toolchain["output_filenames"]["exec"].clone;
                binname.gsub!(/\@[Nn][Aa][Mm][Ee]\@/, @outputName);
                binpath = File.join(buildDir, binname);

                if (!File.exists?(binpath) || source_modified) then
                    puts "- Building executable #{binname}!";
                    cmd = "#{@compiler} #{includes}"
                    cmd += " #{@flags.join(" ")}" if (@flags.size > 0)
                    cmd += " #{@toolchain["flags"]["output"]} #{binpath} #{objFiles.join(" ")} #{libs}";
                    puts "  - $ #{cmd}";
                    f = system(cmd);
                    return f;
                else
                    puts "- No need for building binary, nothing changed!";
                end
            end

            return true;
        end

        public
        # Installs the project
        def install()
            dir = (File.expand_path(OPTIONS[:installDir]) || "/usr/local") if (isLinux? || isMac?)
            dir = (File.expand_path(OPTIONS[:installDir]) || "C:/Program Files/#{@outputName}") if (isWindows?)

            puts "RBuildSys will install #{@name} to the following location: #{dir}";
            puts "Do you want to proceed? [y/N]: "
            if ( STDIN.readline.strip != "y" ) then
                puts "Aborting installation...";
                exit(1);
            end

            # 1. install all includes
            incDir = File.join(dir, "include", @outputName);
            if (!Dir.exists?(incDir)) then
                puts "- create dir: #{incDir}";
                FileUtils.mkdir_p(incDir);
            end

            @public_inc_dirs.each {|d|
                files = Dir.glob(File.join("#{d}", "**/*.{h,hpp}"));
                files.each {|f|
                    dest = File.join(incDir, f.gsub(d, ""));
                    puts "- install: #{dest}";
                    destDir = File.dirname(dest);
                    if (!Dir.exists?(destDir)) then
                        puts "- create dir: #{destDir}";
                        FileUtils.mkdir_p(destDir);
                    end
                    FileUtils.copy_file(f, dest)
                }
            }

            # 2.1 install library results (if any)
            buildDir = "./build/#{@name}";
            if (@libType) then
                libDir = File.join(dir, "lib");
                if (!Dir.exists?(libDir)) then
                    puts "- create dir: #{libDir}";
                    FileUtils.mkdir_p(libDir);
                end

                files = Dir.glob(File.join(buildDir, "*.{a,lib,so,dll}"));  # TODO: this glob should based on the toolchain definition
                files.each {|f|
                    dest = File.join(libDir, f.gsub(buildDir, ""));
                    puts "- install: #{dest}";
                    FileUtils.copy_file(f, dest)
                }

                # install definitions so we can use them in other projects easier!
                metadataDir = File.join(libDir, "rbuildsys_conf");
                if (!Dir.exists?(metadataDir)) then
                    puts "- create dir: #{metadataDir}";
                    FileUtils.mkdir_p(metadataDir);
                end
                metadataFile = File.join(metadataDir, "#{@outputName}.config.json");
                puts "- install: #{metadataFile}";
                FileUtils.copy_file(File.join(buildDir, "#{@outputName}.config.json"), metadataFile);
            end

            # 2.2 install executable results
            if (!@libType) then
                raise NotImplementedError.new("installation of executables (*.exe, *.run etc.) is not supported yet");
            end

        end
    end

    # Stores all projects that are defined by the user
    PROJECTS = {};

    private
    DECLARED_PROJECTS = [];

    # Holds the current project that is currently being configured.
    # Only non-nil inside the block for {#newProject}
    @@cur_proj = nil;

    # Stores all options; will be modified through the commandline option parser
    # @see @@optparse
    OPTIONS = {
        # true if the current build should be a debug build
        :debug   => true,

        # true if we only want to clean our build directory
        :clean   => false,

        # true if we want to make a clean rebuild for only the specified project(s)
        :cleanBuild => false,

        # true if we want to make a clean rebuild for the specified project(s) and its dependencys
        :cleanBuildAll => false,

        # true if we want to install instead of building
        :install => false,

        # contains the path where to install the project(s)
        :installDir => ENV["RBUILDSYS_INSTALLDIR"],

        # overrides the default toolchain specified in the build-script
        :toolchainOverride => nil,
    };

    # Stores all currently loaded toolchains
    TOOLCHAINS = {};

    # Stores all global symbols to configure files
    CONFIG_SYMBOLS = {};

    # Option parser of RBuildSys, used to provide standard operations such as clean, clean build, install...
    @@optparse = OptionParser.new do |opts|

        class MyBanner
            def to_s
                gemDir = File.dirname(File.expand_path(__FILE__));
                toolchains = Dir.glob("#{gemDir}/toolchains/*.json");
                toolchains.map!{|f| File.basename(f, '.json') }

                return  "Usage: #{$PROGRAM_NAME} [options] <projects>\n" +
                        "Projects:\n" +
                        "    " + (PROJECTS.keys + DECLARED_PROJECTS).join(", ") + "\n" +
                        "Toolchains:\n" +
                        "    builtin: " + toolchains.join(", ") + "\n" +
                        "    user   : " + (TOOLCHAINS.keys - toolchains).join(", ") + "\n" +
                        "Options:";
            end
        end
        opts.banner = MyBanner.new();

        opts.on("-r","--release", "Build for release") do
            # todo: if compiled for debug before, the system cannot detect the change
            OPTIONS[:debug] = false;
        end
        opts.on("--rebuild", "Make a clean rebuild only for the given project(s)") do
            OPTIONS[:cleanBuild] = true;
        end
        opts.on("--rebuild-all", "Make a clean rebuild for the given project(s) and its dependencys") do
            OPTIONS[:cleanBuildAll] = true;
        end
        opts.on("-c", "--clean", "Clean the build dirs for the given project(s)") do
            OPTIONS[:clean] = true;
        end
        opts.on("-i", "--install[=DIR]", "Install all project(s) that are installable") do |dir|
            if (dir) then
                OPTIONS[:installDir] = dir;
            end
            OPTIONS[:install] = true;
        end
        opts.on("--installDir=DIR", "Sets the directory to use for installation, and search for installed projects. Can also be configured with the environment variable $RBUILDSYS_INSTALLDIR.") do |dir|
            OPTIONS[:installDir] = dir;
        end
        opts.on("-t TOOLCHAIN", "--toolchain=TOOLCHAIN", "Use the specifed toolchain to build the project and its dependencys") do |toolchain|
            if (toolchain =~ /^[a-zA-Z0-9\_\-]+$/) then
                OPTIONS[:toolchainOverride] = toolchain;
            else
                if (File.exists?(toolchain)) then
                    OPTIONS[:toolchainOverride] = RBuildSys.loadToolchain(toolchain)["name"];
                else
                    raise RuntimeError.new("Commandline argument for toolchain must either be a alpha-numeric-underscore name or an filename!");
                end
            end
        end
        opts.on("-sKEY=VALUE", "Sets the symbol KEY to VALUE for config files") do |str|
            # TODO: this might be not enough to override options already set in projects
            data = str.split("=");
            CONFIG_SYMBOLS[data[0]] = data[1];
        end
    end

    # Creates a new project to build.
    # Takes a block to execute, that defines the project. The block is immediately executed,
    # and has access to the current project (that is created with this method) in {RBuildSys::@@cur_proj RBuildSys::@@cur_proj}.
    #
    # @yield Block to configure the project
    #
    # @param name [String] Name of the project, also used for the final output of the project
    # @param options [Hash] Various options; for details see {Project#initialize}
    def newProject(name, options = {})
        raise ArgumentError.new("Argument #1 (name) need to be a string") if (name.class != String);
        raise ArgumentError.new("Argument #2 (options) need to be an hash") if (!options.is_a?(Hash));

        @@cur_proj = Project.new(name, options);
        yield
        PROJECTS[name] = @@cur_proj;
        @@cur_proj = nil;
    end

    # Begins the build process.
    # Should be called after you configured all your projects with {#newProject}.
    def build()
        parseARGV();
        ARGV.each { |projname|
            proj = PROJECTS[projname];
            if (proj) then
                if (OPTIONS[:clean]) then
                    proj.clean();
                elsif (OPTIONS[:install]) then
                    proj.install();
                else
                    proj.build();
                end
            end
        }
    end

    # Parses the commandline arguments
    # @note this should be called before any call to {#newProject} and/or {#build}!
    def parseARGV()
        @@optparse.parse!
        if (ARGV.length == 0) then
            puts @@optparse;
            exit(1);
        end
    end

    # Declares the project's name so they can be displayed in the help text!
    def declareProjects(*projects)
        DECLARED_PROJECTS.push(*projects);
    end

    # Returns the version of RBuildSys
    # @return ["1.0.0"]
    def sysVersion()
        return "1.0.0";
    end

    # Checks if this RBuildSys is at minimum the required version.
    # This is only for scripts that dont use systems like bundler etc.
    # If you use bundler or similar dependency management software, you propably should use their features instead of this.
    # @return [Boolean]
    def checkSysVersion(min_version)
        data_min = min_version.split(".");
        data_ver = sysVersion().split(".");
        
        if (data_ver.size != data_min.size) then
            return false;
        end
        if (data_ver.size == 4 && data_ver[3] != data_min[3]) then
            # 4th part dosnt match. Should be something like 'pre' or similar.
            return false;
        end

        data_min.pop();
        data_ver.pop();

        while (data_ver.size > 0) do
            a = data_min.pop();
            b = data_ver.pop();
            return false if (a > b);
        end

        return true;
    end

    #########################################################################################
    #   Project configuration                                                               #
    #########################################################################################

    # Adds include directorys to use for the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @param dir [String, Array<String>] Directory path; root of the include path. If its a Array, each element is used in a call to {#incDir}
    # @param more [Array<String>] Additional include paths; each element is used in a call to {#incDir}
    def incDir(dir, *more)
        if (dir.class == String) then
            dirPath = File.join(@@cur_proj.baseDir, dir);
            raise ArgumentError.new("Argument #1 is no directory: '#{dir}' ('#{dirPath}')") if (!Dir.exists?(dirPath));
            @@cur_proj.inc_dirs.push(dirPath);
        elsif (dir.class == Array) then
            dir.each { |d| incDir(d) }
        else
            raise ArgumentError.new("Argument #1 must be a String or an Array");
        end
        more.each { |d| incDir(d) }
    end

    # Adds include directorys to use for projects that depends on the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @param dir [String, Array<String>] Directory path; root of the include path. If its a Array, each element is used in a call to {#publish_incDir}
    # @param more [Array<String>] Additional include paths; each element is used in a call to {#publish_incDir}
    def publish_incDir(dir, *more)
        if (@@cur_proj.libType == nil) then
            raise RuntimeError.new("Can only be called when the project is configured as an library");
        end

        if (dir.class == String) then
            dirPath = File.join(@@cur_proj.baseDir, dir);
            raise ArgumentError.new("Argument #1 is no directory: '#{dir}' ('#{dirPath}')") if (!Dir.exists?(dirPath));
            @@cur_proj.public_inc_dirs.push(dirPath);
        elsif (dir.class == Array) then
            dir.each { |d| publish_incDir(d) }
        else
            raise ArgumentError.new("Argument #1 must be a String or an Array");
        end
        more.each { |d| publish_incDir(d) }
    end

    # Adds source directorys to use for the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @param dir [String, Array<String>] Directory path; root of the source path. If its a Array, each element is used in a call to {#srcDir}
    # @param more [Array<String>] Additional source paths; each element is used in a call to {#srcDir}
    def srcDir(dir, *more)
        if (dir.class == String) then
            dirPath = File.join(@@cur_proj.baseDir, dir);
            raise ArgumentError.new("Argument #1 is no directory: '#{dir}' ('#{dirPath}')") if (!Dir.exists?(dirPath));
            @@cur_proj.src_dirs.push(dirPath);
        elsif (dir.class == Array) then
            dir.each { |d| srcDir(d) }
        else
            raise ArgumentError.new("Argument #1 must be a String or an Array");
        end
        more.each { |d| srcDir(d) }
    end

    # Adds a source glob to use for the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @param glob [String, Array<String>] Glob to be used to find source files; If its a Array, each element is used in a call to {#srcGlob}
    # @param more [Array<String>] Additional source globs; each element is used in a call to {#srcGlob}
    def srcGlob(glob, *more)
        if (glob.class == String) then
            @@cur_proj.src_globs.push(File.join(@@cur_proj.baseDir, glob));
        elsif (glob.class == Array) then
            glob.each { |g| srcGlob(g) }
        else
            raise ArgumentError.new("Argument #1 must be a String or an Array");
        end
        more.each { |g| srcGlob(g) }
    end

    # Tells the current project that it is not install-able
    # This means that if you run an install of your projects, this one will not be installed
    #
    # @note Should only be called inside the block for {#newProject}
    def noInstall()
        @@cur_proj.no_install = true;
    end

    # Sets the current project as a lib
    #
    # @note Should only be called inside the block for {#newProject}
    # @param type [:static, :dynamic, :s, :dyn, :both] The type of the library: static (*.a / *.lib) or dynamic (*.so / *.dll)
    def isLib(type)
        @@cur_proj.libType = :static if ([:static, :s].include?(type));
        @@cur_proj.libType = :dynamic if ([:dynamic, :dyn, :d].include?(type));
        @@cur_proj.libType = :both if (type == :both);
        raise ArgumentError.new("Argument #1 (type) must be one of the following: :static, :dynamic, :s, :dyn, :both") if (@@cur_proj.libType == nil)
    end

    # Returns the install path for the current project
    #
    # @note Should only be called inside the block for {#newProject}
    def getInstallPath()
        dir = OPTIONS[:installDir] || "/usr/include" if (isLinux? || isMac?);
        dir = OPTIONS[:installDir] || "C:/Program Files/#{@@cur_proj.outputName}" if (isWindows?);
        return File.expand_path(dir);
    end

    # Links a RBuildSys project to the current project.
    # This has the effect that the given project is build before the current project, and
    # if the given project is a lib, it is also linked to the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @param name [String] Can be a local project (inside current file) or any installed project
    # @param linktype [:static, :dynamic] Specify wich linkage type should be used to link the project with the current one.
    #                                       If the project to link dosnt support the linktype, this raises an error.
    def use(name, linktype)
        if (PROJECTS[name] == nil) then
            @@cur_proj.dependencys.push([name, linktype]);
        else
            # use local
            proj = PROJECTS[name];

            if (!proj.libType) then
                raise ArgumentError.new("Argument #1 can't be used cause it is not a library");
            end
            if (proj.libType != linktype && proj.libType != :both) then
                raise ArgumentError.new("Argument #1 can't be linked with linktype #{linktype}!");
            end
    
            @@cur_proj.dependencys.push(proj);
        end
    end

    # Adds a external library through pkg-config.
    # If no pkg-config is installed on the system, this functions raises an error
    #
    # @note Should only be called inside the block for {#newProject}
    # @note For retriving the flags from pkg-config, +--libs+ and +--cflags+ is used, and the output is given to {#flag}
    # @param name [String] Name of the pkg-config package
    def usePkgconf(name)
        if (`which pkg-config` == "") then
            raise ArgumentError.new("Option pkgconf specified, but no pkg-config installed on system!");
        end

        modver = `pkg-config --short-errors --modversion #{name}`;
        if (modver.start_with?("No package") or $?.exitstatus != 0) then
            raise RuntimeError.new("Could not find package '#{name}' with pkg-config!");
        end

        linker_flags = `pkg-config --short-errors --libs #{name}`;
        if ($?.exitstatus != 0) then
            raise RuntimeError.new("Could not get linkler flags for '#{name}', plg-config error: #{linker_flags}");
        end
        flag(linker_flags);

        cflags = `pkg-config --short-errors --cflags #{name}`;
        if ($?.exitstatus != 0) then
            raise RuntimeError.new("Could not get compiler flags for '#{name}', plg-config error: #{linker_flags}");
        end
        flag(cflags);
    end

    # Adds a external library to the current project
    #
    # @note Should only be called inside the block for {#newProject}
    # @note There is currently no check in place to verify that the given library exists
    # @param name [String] Name of the library that should be used. in a c/c++ context, it should be without the leading "lib"
    # @param path [String, nil] Optional search path for this library
    # @param options [Hash] Optional options
    # @option options :pkgconf [Boolean] If true, search pkgconf(ig) for additional informations about the lib
    def useLib(name, path = nil, options = {})
        if (options[:pkgconf]) then
            usePkgconf(name);
            return;
        end

        @@cur_proj.librarys.push(name);
        @@cur_proj.lib_dirs.push(path) if (path != nil && Dir.exists?(path));
    end

    # Adds a define to the compiler call
    #
    # @note Should only be called inside the block for {#newProject}
    # @param symbol [String] Symbol that should be defined
    # @param value [String, nil] Optional value the symbol should hold
    def define(symbol, value = nil)
        @@cur_proj.defines[symbol] = value;
    end

    # Adds a flag to the flags of the current project.
    #
    # @note Should only be called inside the block for {#newProject}
    # @note This should only be used when nothing else works, because this method dosnt ensure that the flags used are working with the current toolchain!
    # @param flag [String] the flag to be added
    def flag(flag)
        @@cur_proj.flags.push(flag);
    end

    #########################################################################################
    #   Option parsing                                                                      #
    #########################################################################################

    # Adds an option to the option parser of RBuildSys
    # @see OptionParser#on
    def onOption(*opts, &block)
        @@optparse.on(*opts, block);
    end

    # Adds an option to the option parser of RBuildSys
    # @see OptionParser#on_tail
    def onTailOption(*opts, &block)
        @@optparse.on_tail(*opts, block);
    end

    # Adds an option to the option parser of RBuildSys
    # @see OptionParser#on_head
    def onHeadOption(*opts, &block)
        @@optparse.on_head(*opts, block);
    end

    #########################################################################################
    #   Toolchains                                                                          #
    #########################################################################################

    # Loads a toolchain definition from a file. Format needs to be JSON.
    #
    # @param file [String] path to the toolchain definition file
    def self.loadToolchain(file)
        if (!File.exists?(file)) then
            raise ArgumentError.new("Argument #1 (file) needs to be the path to an existing file");
        end

        data = JSON.parse(File.read(file));
        if (TOOLCHAINS.keys.include?(data["name"])) then
            raise RuntimeError.new("Cannot load toolchain '#{data["name"]}' from '#{file}': already loaded");
        end
        TOOLCHAINS[data["name"]] = data;

        return data;
    end

    private
    def self.load_default_toolchains
        # load builtin toolchains
        gemDir = File.dirname(File.expand_path(__FILE__));
        toolchains = Dir.glob("#{gemDir}/toolchains/*.json");
        toolchains.each {|f|
            self.loadToolchain(f);
        }

        # use toolchain installed for the user
        toolchains = Dir.glob("#{Dir.home}/.rbuildsys/toolchains/*.json");
        toolchains.each {|f|
            self.loadToolchain(f);
        }
    end
    load_default_toolchains()

    #########################################################################################
    #   Configure files                                                                     #
    #########################################################################################

    public
    # Sets a symbol with an optional value to configure files. See {#configureFile}
    #
    # @note When used inside the block for {#newProject}, the symbol is only visible for the project. If used outside of the block, the symbol is visible for everyone!
    # @param symbol [String] The symbol that should be set
    # @param value [String, nil] Optional value for the symbol
    def set(symbol, value = nil)
        if (@@cur_proj == nil) then
            CONFIG_SYMBOLS[symbol] = value;
        else
            @@cur_proj.config_symbols[symbol] = value;
        end
    end

    # Tells the project that, in order to build it, the file specified at +input+ must be transformed to the file at +output+.
    #
    # @note Should only be called inside the block for {#newProject}
    # @param input [String] The filename of the file that should be configured
    # @param output [String] The filename that should be used to save the result, cannot be the same as the input!
    # @param options [Hash] Some optional options
    def configureFile(input, output, options = {})
        if (!input.is_a?(String) || input.strip.empty?) then
            raise ArgumentError.new("Argument #1 (input) needs to be a string");
        end
        
        if (!output.is_a?(String) || output.strip.empty?) then
            raise ArgumentError.new("Argument #2 (output) needs to be a string");
        end

        if (input == output) then
            raise ArgumentError.new("Argument #1 (input) and #2 (output) cannot be the same");
        end

        @@cur_proj.config_files.push({
            input: File.join(@@cur_proj.baseDir, input),
            output: File.join(@@cur_proj.baseDir, output),
            options: options
        });
    end

    #########################################################################################
    #   Utils                                                                               #
    #########################################################################################

    # Shorthand for {Project#isWindows?}
    def isWindows?()
        return @@cur_proj.isWindows?;
    end

    # Shorthand for {Project#isMac?}
    def isMac?()
        return @@cur_proj.isMac?;
    end

    # Shorthand for {Project#isMac?}
    def isLinux?()
        return @@cur_proj.isLinux?;
    end

    # Tests if the toolchain is the given type of OS.
    #
    # @param type [:win, :win32, :windows, :mac, :macos, :apple, :linux] the OS to check
    # @return [Boolean] Returns true if OS is correct, false otherwise
    def isToolchainOS?(type)
        if ([:win, :win32, :windows].include?(type)) then
            return @@cur_proj.isWindows?;
        end

        if ([:mac, :macos, :apple].include?(type)) then
            return @@cur_proj.isMac?();
        end

        if ([:linux].include?(type)) then
            return @@cur_proj.isLinux?();
        end

        raise ArgumentError.new("Unexpected argument: os-type '#{type}' unknown");
    end

end