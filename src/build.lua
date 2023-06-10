!(
    function popen(n)
        local c = io.popen(n)
        local content = c:read("*a")
        c:close()
        return content
    end
    function string_split(string,delimiter)
        local n = {}
        for match in (string..delimiter):gmatch("(.-)"..delimiter) do
            table.insert(n,match)
        end
        return n
    end
    local table_find = table.find or function(table,pin)
        for i,v in pairs(table) do if v==pin then return i end end
    end
    build = {
        branch=popen("git rev-parse --abbrev-ref HEAD"):sub(1,-2);
        hash=popen("git log -1 --format=%h"):sub(1,-2);--string_split(popen("git show-ref"),"%s")[1];
        last_commit=popen("git log -1 --format=%cd"):sub(1,-2);
        build_date=os.date("%a %b %d %X %Y");
    }
)