# Toolchain Format

This file serves as specification for the toolchain definition format.

## Example

The following example can also be found at `lib/toolchain/gnu.json` (but without the comments!)
```json
{
    "name": "gnu",          // name of the toolchain, must be uniqe! Must also be the name of the file

    "os": "linux",          // operating system the toolchain targets; aviable are: linux, windows, macos

    "compiler": {           // this object defines the binarys that are called for the different languages
        "c": "gcc",
        "c++": "g++"
    },
    "archiver": "ar",       // archiver that should be used when building a static library

    "flags": {              // this object defines all flags that can be used for a specific goal
        "debug": "-g",      // for example: this line defines that in order to produce a debug build, the flag -g must be passed to the compiler binary

        "include": "-I",    // flag to specify include paths
        "libPath": "-L",    // flag to specify additional library paths
        "libLink": "-l",    // flag to specify wich library the result should be linked against
        "output": "-o",     // flag to specify the output filename
        "allWarnings": "-Wall", // flag to specify that the compiler should print out all warnings it detects
        "pic": "-fPIC",     // flag to generate position independent code, which is needed for a dynamic library/object file 
        "langStd": "-std",  // flag to specify the language standard that should be used
        "define": "-D"      // flag to define additional symbols and optional its value
    },

    "output_filenames": {               // this object defines varios patterns that should be used to name output files
        "exec": "@NAME@.run",           // pattern used for executables
        "staticLib": "lib@NAME@.a",     // pattern used for static librarys
        "dynamicLib": "lib@NAME@.so"    // pattern used for dynamic librarys
    },

    "extra_flags": ""       // this key is used for extra flags that should always be added to each call to the compiler
}
```
