#!/usr/bin/env lua

--[[
    The MIT License

    Copyright (C) 2017 Saravjeet 'Aman' Singh
    <saravjeetamansingh@gmail.com>

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

--[[
    pack.lua -- a module bundler for lua 5.1

    usage: 
        pack.lua <toplevel-module>.lua

        this will create a file called <toplevel-module>.bundle.lua in the
        current directory

    features:
        * supports relative imports.
        * imported modules are only evaluated once.
        * works well with luarocks and other lua modules. (however, luarocks
          modules are not bundled, sadly)

    requirements:
        pack.lua has been tested on lua 5.1 and only supports the new style
        module system.

        also, it only works on a POSIX system. (:


    information:
        pack.lua wraps and bundles a lua source tree into a single source file.

        The primary motivation for this script was to make it easier to write
        lua source to bundle as part of a C library.

        A neat trick that you can do is to use `luac` to compile the source and
        then use the tool `xxd` to generate a C header that can then directly
        be included into your C/C++ source. This is awesome because you cant
        actually see the lua source on inspecting the executable output. 

    warning:
        pack.lua does not check for, or eliminate circular dependencies.

        if you have a circular dependency somewhere in your source tree,
        pack.lua will probably crash the call stack.
]]

-- map module path to modules array
local print_to_console = false -- print to console on end

-- contains source for modules
local modules = {}

local luapack_header = [[
local __pack
__pack={
	modules = {
		%s
	};
	cache = {};
}
__pack.require = function(idx)
    local cache = __pack.cache[idx]
    if cache then
        return cache
    end

    local module = __pack.modules[idx]()
    __pack.cache[idx] = module
    return module
end
]]

-- python-like path helpers
local path
path = {
    isrelative = function(path) 
        return path:sub(1, 1) ~= '/'
    end,
    isabsolute = function(path) 
        return path:sub(1, 1) == '/'
    end,
    join = function(base, addon)

        -- addon path must be relative
        if path.isabsolute(addon) then
            return addon
        end

        -- prepare the base path, and make sure it points to a directory
        if path.isrelative(base) then
            base = path.abspath(base)
        end
        if path.isfile(base) then
            base = path.dirname(base)
        end

        -- join
        local newpath = base .. '/' .. addon

        -- normalise
        newpath = path.abspath(newpath)

        -- realpath failed
        if newpath:sub(1, 1) ~= '/' then
            return addon
        end

        return newpath 
    end,
    isdir = function(path)
        return os.execute("test -d \""..path.."\"") == 0
    end,
    isfile = function(path)
        return os.execute("test -f \""..path.."\"") == 0
    end,
    abspath = function(path)
        local cmd = string.format("realpath --relative-to=\"$(pwd)\" --quiet \"%s\"", path)
        return strip(io.popen(cmd):read("*a"))
    end,
    basename = function(path)
        local cmd = string.format("basename \"%s\"", path)
        return strip(io.popen(cmd):read("*a"))
    end,
    dirname = function(path)
        local cmd = string.format("dirname \"%s\"", path)
        return strip(io.popen(cmd):read("*a"))
    end
}

function strip(str)
    return string.gsub(str, "%s", "")
end
local gsub_keywords = {
	['(']=true;
	[')']=true;
	['[']=true;
	[']']=true;
	['.']=true;
	['%']=true;
	['$']=true;
	['^']=true;
	['*']=true;
}
function gsub_escape(str)
	return str:gsub('.',function(c)
		if gsub_keywords[c] then
			return '%'..c
		end
		return c
	end)
end

function require_string(idx,y)
    if y then return "__pack%.require%((%w*)%)" end
    return string.format("__pack.require('"..(type(idx) == "string" and "%s" or "%d").."')", idx)
end

function import(module_path,method)
    if modules[module_path] then
	    if not print_to_console then print('cached',module_path) end
    else
        if not print_to_console then print('import',module_path) end
        local fd, err = io.open(module_path,'r')
        if fd==nil then error(err) end
        local source = fd:read("*a")
        io.close(fd)
        if source:sub(1,4)=="\27Lua" then error('TODO: bytecode support') end
        modules[module_path] = ' --[[PLACEHOLDER]] '
        source = transform(source, module_path, method)
        modules[module_path] = source
    end
    return require_string(module_path)
end

function transform(source, source_path, method)
    if method==nil or method=="static" then
        local splitsource = {}
        for v in source:gmatch('(.-)\n') do
           table.insert(splitsource,v)
        end
        if splitsource[1]:sub(1,1) == "#" then
            table.remove(splitsource,1)
            source=table.concat(splitsource,"\n")
        end
        local context = path.abspath(path.dirname(source_path))
        local pattern = "require%s*%(?%s*[\"'](.-)[\"']%s*%)?"
        local pattern2 = "dofile%s*%(?%s*[\"'](.-)[\"']%s*%)?"
    
        return string.gsub(string.gsub(source, pattern, function(name)
                name=name:gsub('%.','/')
                local path_to_module = path.join(context, name)
                --print(path_to_module)
                if path.isdir(path_to_module) then
                    path_to_module=path_to_module.."/init.lua"
                end
                if not (path.isfile(path_to_module) or path.isfile(path_to_module..".lua")) then
                    return nil
                end

                if path.isfile(path_to_module) then
                    return import(path_to_module,method)--..'\n'
                else
                    return import(path_to_module..".lua",method)--.."\n"
                end
            end), pattern2, function(name)
                
            local path_to_module = path.join(context, name)
            --print(path_to_module)
            if not (path.isfile(path_to_module) or path.isfile(path_to_module..".lua")) then
                return nil
            end
            if path.isfile(path_to_module) then
                return import(path_to_module,method)--.."\n"
            else
                return import(path_to_module..".lua",method)--.."\n"
            end
        end)
    end
end

function generate_module_header()

    function left_pad(source, padding, ch)
        ch = ch or ' '
        local repl = function(str)
            return string.rep(ch, padding) .. str
        end
        return string.gsub(source, '(.-\n)', repl)
    end

    function pad(source,mp)
        source = left_pad(source, 4)
        source = string.format('["%s"] = (function(...)\n%s\nend),\n', mp, source)
        source = left_pad(source, 4)
        return source
    end
    local modstring = ''
    local inc = 0
    for i,v in pairs(modules) do
        modstring = modstring .. pad(v,i)
    	inc=inc+1
    end
    if inc == 0 then return '' end
    local header = string.format(luapack_header, modstring)
    return header
end

function main(argv)
    if #argv == 0 then
        local usage = string.format('usage: %s <toplevel-module>.lua', argv[0])
        print(usage)
        return -1
    end

    local entry = argv[1]
    local fd, err = io.open(entry)
    if fd == nil then
        error(err)
    end
    local source = fd:read("*a")
    fd:close()
    local path_to_entry = path.abspath(entry)
    source = transform(source, path_to_entry,"static")
    local header = generate_module_header()

    source = header..'\n'..source
    if print_to_console then print(source) return 0 end

    local out = argv[2]
    if out==nil then
	out = string.gsub(entry, "%.lua", "")
    	out = out..".bundle.lua"
    	out = path.basename(out)
    end
    io.open(out, "w"):write(source)

    return 0
end

os.exit(main(arg))
