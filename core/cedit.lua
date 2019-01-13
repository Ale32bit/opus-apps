local read  = _G.read
local shell = _ENV.shell

if not _G.cloud_catcher then
  print('Paste key: ')
  local key = read()
  if #key == 0 then
    return
  end
  shell.openHiddenTab('cloud ' .. key)
end

shell.run('cloud edit ' .. table.unpack({ ... }))
