require "optparse"
require "fileutils"

# Namespace for all code for RBuildSys
module RBuildSys

    # Class to describe a buildable RBuildSys project
    #
    # @author Mai-Lapyst
    class Project
        # Returns the name of the project
        # @return [String]
        attr_reader :name

        # Returns the array of source directorys for this project
        # @return [Array<String>]
        attr_reader :src_dirs

        # Returns the array of include directorys for this project
        # @return [Array<String>]
        attr_reader :inc_dirs

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

        # Returns the library type of this project; if nil, this project isn't a library
        # @return [:static, :dynamic, :s, :dyn]
        attr_accessor :libType

        # Returns the dependencys of this project
        # @return [Array<Project>]
        attr_reader :dependencys

        # @param name [String] name of the project; see {#name}
        # @param options [Hash] various options for the project
        # @option options :lang [Symbol] language used for this project. Available: +:c+, +:cpp+
        # @option options :srcFile_endings [Array<String>] additional fileendings that should be used for finding sourcefiles
        # @option options :no_install [true, false] flag that tells if the project is install-able or not; see {#no_install}
        # @option options :libType [:static, :dynamic, :s, :dyn, nil] type of library; see {#libType}
        # @option options :compiler [String, nil] compiler to be used to transform sourcefiles to objectfiles; if no is supplied, +"gcc"+ or +"g++"+ is used (based on the language)
        def initialize(name, options)
            @name = name;
            @src_dirs = [];
            @inc_dirs = [];
            @lib_dirs = [];
            @dependencys = [];
            @librarys = [];
            @flags = [];

            check_lang(options[:lang] || "c");

            @compiler = "gcc" if (@lang == :c);
            @compiler = "g++" if (@lang == :cpp);
            if (options[:compiler]) then
                @compiler = options[:compiler];
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
        end

        private
        # lang must be a valid string for the gcc/g++ -std option:
        # https://gcc.gnu.org/onlinedocs/gcc/C-Dialect-Options.html
        # or simply the language: c, c++, gnu, gnu++
        def check_lang(lang)
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

            raise ArgumentError.new("argument #2 contains key lang, but cannot validate it: '#{lang}'");
        end

        public
        # cleans the project's output directory
        def clean()
            buildDir = "./build/#{name}";
            FileUtils.remove_dir(buildDir) if File.directory?(buildDir)
        end

        public
        # builds the project
        # @return [true, false] state of the build, true means success, false means failure
        def build()
            for dep in dependencys do
                if (!dep.build()) then
                    return false;
                end
            end

            puts "Now building '#{@name}'";
            puts "- using language #{@lang}";

            for dep in dependencys do
                @inc_dirs.push(*dep.inc_dirs).uniq!;
                @lib_dirs.push("./build/#{dep.name}");
                @librarys.push(dep.name);
                if (dep.libType == :static) then
                    @lib_dirs.push(*dep.lib_dirs).uniq!
                    @librarys.push(*dep.librarys).uniq!
                end
            end

            @flags.push("-g") if (OPTIONS[:debug]);

            # create the project build dir
            buildDir = "./build/#{name}";
            system("mkdir -p #{buildDir}"); # todo: dont use system!

            # make the includes
            #inc_dirs.map! { |incDir| incDir + "/*.h" }
            #includes = Dir.glob(inc_dirs);
            includes = @inc_dirs.map{|incDir| "-I #{incDir}"}.join(" ");
            libs = @lib_dirs.map{|libDir| "-L #{libDir}"}.join(" ") + " " + @librarys.map{|lib| "-l #{lib}"}.join(" ");
            std = @c_standard ? ("-std=#{@c_standard}") : "";
            
            # for now, just ignore all global and relative paths for sources
            src_dirs.select! { |srcDir|
                srcDir[0] != "/" && !srcDir.start_with?("../")
            }

            source_modified = false;
            build_failed = false;

            src_dirs.each { |srcDir|
                globStr = File.join(srcDir, "**/*.{#{@src_file_endings.join(",")}}");
                srcFiles = Dir.glob(globStr);

                # do the incremental build!
                srcFiles.each { |srcFile|
                    objFile = File.join(buildDir, srcFile.gsub(srcDir, ""));
                    objFile = objFile.gsub(Regexp.new("\.(#{@src_file_endings.join("|")})$"), ".o");
                    srcTime = File.mtime(srcFile);

                    if (OPTIONS[:cleanBuild] || !File.exists?(objFile) || (srcTime > File.mtime(objFile))) then
                        source_modified = true;
                        FileUtils.mkdir_p(File.dirname(objFile));   # ensure we have the parent dir(s)

                        # build the source!
                        cmd = "#{@compiler} #{std} -Wall #{includes} #{@flags.join(" ")} -c -o #{objFile} #{srcFile}";
                        puts "- $ #{cmd}"; 
                        f = system(cmd);
                        if (f) then
                            FileUtils.touch(objFile, :mtime => srcTime);
                        else
                            build_failed = true;
                        end
                    end
                }
            }

            if (build_failed) then
                return false;
            end

            if (!source_modified) then
                puts "- No need for building library/executable, nothing changed!";
                return true;
            end

            objFiles = Dir.glob(buildDir + "/**/*.o");
            if (libType == :static) then
                puts "- Building static library lib#{name}!";
                libname = File.join(buildDir, "lib#{name}.a");
                cmd = "ar rcs #{libname} #{objFiles.join(" ")}";
                puts "  - $ #{cmd}";
                f = system(cmd);
                return f;
            elsif (libType == :dynamic) then
                raise NotImplementedError.new("");
            else
                # build runable binary
                binname = File.join(buildDir, "#{name}.run");
                puts "- Building executable #{binname}!";
                cmd = "#{@compiler} #{includes} #{@flags.join(" ")} -o #{binname} #{objFiles.join(" ")} #{libs}";
                puts "  - $ #{cmd}";
                f = system(cmd);
                return f;
            end

            return true;
        end
    end

    # Stores all projects that are defined by the user
    PROJECTS = {};

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

        # true if we want to clean all buildfiles before building
        :cleanBuild => false,

        # true if we want to install instead of building
        :install => false,
    };

    # Option parser of RBuildSys, used to provide standard operations such as clean, clean build, install...
    @@optparse = OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] <projects>";

        opts.on("-r","--release", "Build for release") do
            # todo: if compiled for debug before, the system cannot detect the change
            OPTIONS[:debug] = false;
        end
        opts.on("-b", "--build-clean", "Make a clean build") do
            OPTIONS[:cleanBuild] = true;
        end
        opts.on("-c", "--clean", "Clean all projects build dirs") do
            OPTIONS[:clean] = true;
        end
        opts.on("-i", "--install", "Install all project(s) that are installable") do
            OPTIONS[:install] = true;
        end
    end

    # creates a new project to build
    # takes a block to execute, that defines the project. it is immediately executed,
    # and has aaccess to the current project (that is created with this method) in {RBuildSys::@@cur_proj RBuildSys::@@cur_proj}.
    #
    # @yield Block to configure the project
    #
    # @param name [String] name of the project, also used for the final output of the project
    # @param options [Hash] various options; for details see {Project#initialize}
    def newProject(name, options = {})
        raise ArgumentError.new("name need to be a string") if (name.class != String);
        @@cur_proj = Project.new(name, options);
        yield
        PROJECTS[name] = @@cur_proj;
        @@cur_proj = nil;
    end

    # adds include directorys to use for the current project
    #
    # @note should only be called inside the block for {#newProject}
    # @param dir [String, Array<String>] directory path; root of the include path. if its a Array, each element is used in a call to {#incDir}
    # @param more [Array<String>] additional include paths; each element is used in a call to {#incDir}
    def incDir(dir, *more)
        if (dir.class == String) then
            raise ArgumentError.new("argument #1 is no directory: '#{dir}'") if (!Dir.exists?(dir));
            @@cur_proj.inc_dirs.push(dir);
        elsif (dir.class == Array) then
            dir.each { |d| incDir(d) }
        else
            raise ArgumentError.new("argument #1 must be a String or an Array");
        end
        more.each { |d| incDir(d) }
    end

    # adds source directorys to use for the current project
    #
    # @note should only be called inside the block for {#newProject}
    # @param dir [String, Array<String>] directory path; root of the source path. if its a Array, each element is used in a call to {#srcDir}
    # @param more [Array<String>] additional source paths; each element is used in a call to {#srcDir}
    def srcDir(dir, *more)
        if (dir.class == String) then
            raise ArgumentError.new("argument #1 is no directory: '#{dir}'") if (!Dir.exists?(dir));
            @@cur_proj.src_dirs.push(dir);
        elsif (dir.class == Array) then
            dir.each { |d| srcDir(d) }
        else
            raise ArgumentError.new("argument #1 must be a String or an Array");
        end
        more.each { |d| srcDir(d) }
    end

    # tells the current project that it is not install-able
    # this means that if you run an install of your projects, this one will not be installed
    #
    # @note should only be called inside the block for {#newProject}
    def noInstall()
        @@cur_proj.no_install = true;
    end

    # sets the current project as a lib
    #
    # @note should only be called inside the block for {#newProject}
    # @param type [:static, :dynamic, :s, :dyn] the type of the library: static (*.a / *.lib) or dynamic (*.so / *.dll)
    def isLib(type)
        @@cur_proj.libType = :static if ([:static, :s].include?(type));
        @@cur_proj.libType = :dynamic if ([:dynamic, :dyn, :d].include?(type));
    end

    # links a RBuildSys project to the current project
    # this has the effect that the given project is build before the current project, and
    # if the given project is a lib, it is also linked to the current project
    #
    # @note should only be called inside the block for {#newProject}
    # @param name [String] can be a local project (inside current file) or any installed project
    def use(name)
        if (PROJECTS[name] == nil) then
            # use installed project
            raise NotImplementedError.new("");
        else
            # use local
            proj = PROJECTS[name];
        end

        if (!proj.libType) then
            raise ArgumentError.new("argument #1 can't be used cause it is not a library");
        end

        @@cur_proj.dependencys.push(proj);
    end

    # adds a external library to the current project
    #
    # @note should only be called inside the block for {#newProject}
    # @note there is currently no check in place to verify that the given library exists
    # @param name [String] name of the library that should be used. in a c/c++ context, it should be without the leading "lib"
    # @param path [String, nil] optional search path for this library
    def useLib(name, path = nil)
        @@cur_proj.librarys.push(name);
        @@cur_proj.lib_dirs.push(path) if (path != nil && Dir.exists?(path));
    end

    # adds an option to the option parser of RBuildSys
    # @see OptionParser#on
    def onOption(*opts, &block)
        @@optparse.on(*opts, block);
    end

    # adds an option to the option parser of RBuildSys
    # @see OptionParser#on_tail
    def onTailOption(*opts, &block)
        @@optparse.on_tail(*opts, block);
    end

    # adds an option to the option parser of RBuildSys
    # @see OptionParser#on_head
    def onHeadOption(*opts, &block)
        @@optparse.on_head(*opts, block);
    end

    # adds a flag to the flags of the current project.
    #
    # @note should only be called inside the block for {#newProject}
    # @param flag [String] the flag to be added
    def flag(flag)
        @@cur_proj.flags.push(flag);
    end

    # begins the build process.
    # should be called after you configured all your projects with {#newProject}.
    def build()
        @@optparse.parse!
        if (ARGV.length == 0) then
            puts @@optparse;
            exit(1);
        end

        ARGV.each { |projname|
            proj = PROJECTS[projname];
            if (proj) then
                if (OPTIONS[:clean]) then
                    proj.clean();
                else
                    proj.build();
                end
            end
        }
    end

end