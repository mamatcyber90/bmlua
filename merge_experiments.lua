#!/usr/bin/lua

-- BUILT-IN/EXTERNAL MODULES
require('os')
require('io')
require('uci')

-- BISMARK (BMLUA) MODULES
require('bmlua.path')
path = bmlua.path
require('bmlua.opkg')
opkg = bmlua.opkg
-- `require('foo.bar'); bar = foo.bar;`
-- is the equivalent of python's `import foo.bar as bar`

------------------------------------------------------------------------------
-- GLOBALS
------------------------------------------------------------------------------
DEBUG = true
UCI_DIR = '/etc/config'
UCI_DIR = 'etc_config'
UCI_CONFIG = 'bismark-experiments'

------------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------------
UCI_TRUE = '1'
UCI_FALSE = '0'

------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
------------------------------------------------------------------------------
function main(arg)
    pdebug("DEBUG MODE ON\n")

    local remote_fullpath
    local remote_dirpath
    local remote_filename
    local remote_uci
    local local_fullpath
    local local_dirpath
    local local_filename
    local local_uci

    if #arg ~= 1 then
        print("  USAGE: " .. arg[0] .. " REMOTE_CONFIG_FILE")
        os.exit(1)
    end

    remote_fullpath = path.abspath(arg[1])
    remote_dirpath = path.dirname(remote_fullpath)
    remote_filename = path.basename(remote_fullpath)
    if not path.exists(remote_dirpath) then
        print(string.format("Remote experiment config directory %q not found",
                remote_dirpath))
        os.exit(1)
    end
    if not path.exists(remote_fullpath) then
        print(string.format("Remote experiment UCI file %q not found",
                remote_fullpath))
        os.exit(1)
    end

    local_fullpath = path.abspath(path.join(UCI_DIR, UCI_CONFIG))
    local_dirpath = path.dirname(local_fullpath)
    local_filename = path.basename(local_fullpath)
    if not path.exists(local_dirpath) then
        print(string.format("Local config directory %q not found", dirpath))
        os.exit(1)
    end
    if not path.exists(local_fullpath) then
        pdebug("UCI file %q does not exist; 'touch'ing.\n", local_fullpath)
        os.execute(string.format('touch %s', local_fullpath))
    end

    remote_uci = uci.cursor(remote_dirpath)
    if DEBUG then
        local_uci = uci.cursor(local_dirpath)
    else
        local_uci = uci.cursor()
    end

    --if DEBUG then
    --    init_be_local_uci(local_uci)
    --    init_be_remote_uci(remote_uci, filename)
    --end

    update_local_experiment_list(UCI_CONFIG, local_uci, remote_uci)
    local_uci:save(UCI_CONFIG)
    local_uci:commit(UCI_CONFIG)
    make_packages_consistent(UCI_CONFIG, local_uci)
end


function update_local_experiment_list(config, local_uci, remote_uci)
    local rem_exps = remote_uci:get_all(config)
    local loc_exps = local_uci:get_all(config)

    -- Insert and update experiments found in remote config file
    for ename,exp in pairs(rem_exps) do
        if loc_exps[ename] == nil then
            local_uci:set(config, ename, 'experiment')
            local_uci:set(config, ename, 'available', UCI_TRUE)
            local_uci:set(config, ename, 'installed', UCI_FALSE)
            pdebug("Experiment %q added to local experiment set.\n", ename)
        else
            pdebug("Updating local experiment %q.\n", ename)
        end
        local_uci:set(config, ename, 'packages', exp.packages)
        local_uci:set(config, ename, 'description', exp.description)
        local_uci:set(config, ename, 'display_name', exp.display_name)
        -- TODO: This update process ignores (will not uninstall) packages that
        --       are initially on the local package list but not on the remote
        --       package list. Perhaps these should be collected in a
        --       'discarded packages' table?
    end

    -- Remove experiments not found in remote config file
    local exps_to_delete = {}
    for ename,exp in pairs(loc_exps) do
        if rem_exps[ename] == nil then
            local_uci:set(config, ename, 'available', UCI_FALSE)
            for i,pname in pairs(exp.packages) do
                if not opkg.info(pname).installed then
                    local_uci:set(config, ename, 'installed', UCI_FALSE)
                    pdebug("Marking experiment %q as not installed because " ..
                            "one of its packages %q is not installed.\n",
                            ename, pname)
                    break
                end
            end
            if not uci_bool(local_uci:get(config, ename, 'installed')) then
                exps_to_delete[#exps_to_delete + 1] = ename
            end
        end
    end
    for i,ename in pairs(exps_to_delete) do
        local_uci:delete(config, ename)
        pdebug("Experiment %q deleted from local experiment set.\n", ename)
    end
end


function make_packages_consistent(config, local_uci)
    local loc_exps = local_uci:get_all(config)

    for ename,exp in pairs(loc_exps) do
        for i,pname in pairs(exp.packages) do
            if (uci_bool(local_uci:get(config, ename, 'installed')) and
                    not opkg.info(pname).installed) then
                pdebug("Installing package %q.\n", pname)
                -- TODO: error handling
                opkg.install(pname)

            elseif (not uci_bool(local_uci:get(config, ename, 'installed')) and
                    opkg.info(pname).installed) then
                if (opkg.depends_on(pname) ~= nil and
                        #opkg.depends_on(pname) == 0) then
                    pdebug("Removing package %q.\n", pname)
                    opkg.remove(pname)
                end
            end
        end
    end
end

function uci_bool(s)
    local retval = nil
    s = s:lower()
    if s == 'true' or s == '1' or s == 'yes' then
        retval = true
    elseif s == 'false' or s == '0' or s == 'no' then
        retval = false
    end
    return retval
end


function pdebug(s, ...)
    if DEBUG ~= nil and DEBUG == true then
        io.stderr:write(string.format(s, unpack(arg)))
    end
end


------------------------------------------------------------------------------
-- TESTING STUFF
------------------------------------------------------------------------------
function init_be_remote_uci(uci_cursor, filename)
    local success = true
    local config_name = filename
    local sec_name = 'wifi_beacons'
    success = success and uci_cursor:set(config_name, sec_name, 'experiment')
    success = success and uci_cursor:set(config_name, sec_name,
            'display_name', 'Wifi Beacons')
    success = success and uci_cursor:set(config_name, sec_name, 'description',
            'Wifi Beacons collects data about the devices connected to your ' ..
            'BISmark router over wireless, as well as the presence of other ' ..
            'nearby wireless access points. <b>Wifi Beacons does not ' ..
            'collect the contents of your network traffic.</b>')
    success = success and uci_cursor:set(config_name, sec_name, 'packages',
            {'wifi_beacons-tmpfs',
             'bismark-data-uploader'})
    if success then
        uci_cursor:commit(config_name)
    else
        print("failure")
    end
end


function init_be_local_uci(uci_cursor)
    local success = true
    local config_name = 'bismark-experiments'
    local sec_name = 'wifi_beacons'
    init_be_remote_uci(uci_cursor, config_name)
    success = success and uci_cursor:set(config_name, sec_name,
            'installed', 'yes')
    success = success and uci_cursor:set(config_name, sec_name,
            'available', 'yes')
    if success then
        uci_cursor:commit(config_name)
    else
        print("failure")
    end
end


------------------------------------------------------------------------------
-- EXECUTE THIS SCRIPT
------------------------------------------------------------------------------
return main(arg)
