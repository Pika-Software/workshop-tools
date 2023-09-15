-- https://github.com/WilliamVenner/gmsv_workshop
if not steamworks and util.IsBinaryModuleInstalled( "workshop" ) and pcall( require, "workshop" ) then
    gpm.Logger:Info( "A third-party steamworks API 'workshop' has been initialized." )
end

local steamworks = steamworks
if not steamworks then
    error( "There is no steamworks library, it is required to work with the Steam Workshop, a supported binary for server side: https://github.com/WilliamVenner/gmsv_workshop" )
end

install( "packages/steam-api.lua", "https://raw.githubusercontent.com/Pika-Software/steam-api/main/lua/packages/steam-api.lua" )

local promise = promise
local ipairs = ipairs
local steam = steam
local table = table
local file = file

local lib = {
    ["Downloads"] = file.CreateDir( "downloads/" .. string.lower( gpm.Realm ) )
}

lib.GetItem = steam.GetPublishedFileDetails
lib.GetCollection = promise.Async( function( ... )
    local ok, result = steam.GetCollectionDetails( ... ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    for number, collection in ipairs( result ) do
        local items = collection.children
        items.wsid = collection.publishedfileid
        result[ number ] = items

        table.sort( items, function( a, b )
            return a.sortorder < b.sortorder
        end )

        local addons, collections = {}, {}
        items.collections = collections
        items.addons = addons

        for index, item in ipairs( items ) do
            items[ index ] = nil

            local fileType = item.filetype
            if fileType == 0 then
                addons[ #addons + 1 ] = item.publishedfileid
            elseif fileType == 2 then
                collections[ #collections + 1 ] = item.publishedfileid
            end
        end
    end

    return result
end )

function lib.DownloadGMA( ... )
    local p = promise.New()
    local tasks = { ... }

    for index, wsid in ipairs( tasks ) do
        local task = { ["wsid"] = wsid }
        tasks[ index ] = task

        steamworks.DownloadUGC( wsid, function( filePath, fileClass )
            if filePath and file.Exists( filePath, "GAME" ) then
                task.successfull = true
            elseif fileClass then
                local content = fileClass:Read( fileClass:Size() )
                fileClass:Close()

                filePath = lib.Downloads .. wsid .. ".gma.dat"
                fileClass = file.Open( filePath, "wb", "DATA" )
                filePath = "data/" .. filePath

                if fileClass then
                    fileClass:Write( content )
                    fileClass:Close()
                    task.successfull = true
                end
            end

            task.filePath = filePath
            task.finished = true

            for _, tbl in ipairs( tasks ) do
                if tbl.finished then continue end
                return
            end

            p:Resolve( tasks )
        end )
    end

    return p
end

function lib.Get( wsid )
    local p = promise.New()

    steamworks.FileInfo( wsid, function( data )
        if not data then
            p:Reject( "failed" )
            return
        end

        p:Resolve( data )
    end )

    return p
end

return lib