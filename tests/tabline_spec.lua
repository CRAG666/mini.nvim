local helpers = require('tests.helpers')

local child = helpers.new_child_neovim()
local eq = assert.are.same

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('tabline', config) end
local unload_module = function() child.mini_unload('tabline') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_lines = function(...) return child.set_lines(...) end
--stylua: ignore end

-- Make helpers
local mock_devicons = function()
  child.cmd([[set rtp+=tests/tabline-tests]])
end

local edit = function(name)
  child.cmd('edit ' .. name)
end

local edit_path = function(rel_path)
  child.cmd('edit tests/tabline-tests/' .. rel_path)
end

local eval_tabline = function(show_hl, show_action)
  local res = child.lua_get('MiniTabline.make_tabline_string()')

  if not show_hl then
    res = res:gsub('%%#%w+#', '')
  end

  if not show_action then
    res = res:gsub('%%%d+@%w+@', '')
    res = res:gsub('%%X', '')
  end

  return res
end

-- Unit tests =================================================================
describe('MiniTabline.setup()', function()
  before_each(function()
    child.setup()
    load_module()
  end)

  it('creates side effects', function()
    -- Global variable
    assert.True(child.lua_get('_G.MiniTabline ~= nil'))

    -- Highlight groups
    local has_highlight = function(group, value)
      assert.truthy(child.cmd_capture('hi ' .. group):find(value))
    end

    has_highlight('MiniTablineCurrent', 'links to TabLineSel')
    has_highlight('MiniTablineVisible', 'links to TabLineSel')
    has_highlight('MiniTablineHidden', 'links to TabLine')
    has_highlight('MiniTablineModifiedCurrent', 'links to StatusLine')
    has_highlight('MiniTablineModifiedVisible', 'links to StatusLine')
    has_highlight('MiniTablineModifiedHidden', 'links to StatusLineNC')
    has_highlight('MiniTablineFill', 'cleared')
    has_highlight('MiniTablineTabpagesection', 'links to Search')
  end)

  it('creates `config` field', function()
    eq(child.lua_get('type(_G.MiniTabline.config)'), 'table')

    -- Check default values
    local assert_config = function(field, value)
      eq(child.lua_get('MiniTabline.config.' .. field), value)
    end

    assert_config('show_icons', true)
    assert_config('set_vim_settings', true)
    assert_config('tabpage_section', 'left')
  end)

  it('respects `config` argument', function()
    reload_module({ set_vim_settings = false })
    eq(child.lua_get('MiniTabline.config.set_vim_settings'), false)
  end)

  it('validates `config` argument', function()
    unload_module()

    local assert_config_error = function(config, name, target_type)
      assert.error_matches(function()
        load_module(config)
      end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
    end

    assert_config_error('a', 'config', 'table')
    assert_config_error({ show_icons = 'a' }, 'show_icons', 'boolean')
    assert_config_error({ set_vim_settings = 'a' }, 'set_vim_settings', 'boolean')
    assert_config_error({ tabpage_section = 1 }, 'tabpage_section', 'string')
  end)

  it("sets proper 'tabline' option", function()
    -- Uses custom function in case of single and multiple tabpages
    eq(child.api.nvim_get_option('tabline'), '%!v:lua.MiniTabline.make_tabline_string()')

    child.cmd([[tabedit]])
    eq(child.api.nvim_get_option('tabline'), '%!v:lua.MiniTabline.make_tabline_string()')
  end)

  it('respects `config.set_vim_settings`', function()
    reload_module({ set_vim_settings = true })
    eq(child.o.showtabline, 2)
    eq(child.o.hidden, true)
  end)
end)

describe('MiniTabline.make_tabline_string()', function()
  before_each(function()
    child.setup()
    load_module()
  end)

  it('works', function()
    child.cmd('edit aaa')
    local buf_aaa = child.api.nvim_get_current_buf()
    child.cmd('edit bbb')
    local buf_bbb = child.api.nvim_get_current_buf()
    --stylua: ignore
    eq(
      eval_tabline(true, true),
      table.concat({
        '%#MiniTablineHidden#',
        '%', buf_aaa, '@MiniTablineSwitchBuffer@',
        ' aaa ',
        '%#MiniTablineCurrent#',
        '%', buf_bbb, '@MiniTablineSwitchBuffer@',
        ' bbb ',
        '%X%#MiniTablineFill#',
      })
    )
  end)

  it('works with unnamed buffers', function()
    -- Labels: `*` for regular unnamed and `!` for scratch buffer
    child.api.nvim_create_buf(true, true)
    eq(eval_tabline(true), '%#MiniTablineCurrent# * %#MiniTablineHidden# !(2) %#MiniTablineFill#')
  end)

  it('works with quickfix and location lists', function()
    child.cmd('edit aaa')
    set_lines({ 'AAA' })

    -- Quickfix list
    child.cmd('cbuffer | copen')
    eq(eval_tabline(), ' aaa  *quickfix*(2) ')

    child.cmd('q')

    -- Location list
    child.cmd('lbuffer | lopen')
    eq(eval_tabline(), ' aaa  *quickfix*(3) ')
  end)

  it('respects `config.tabpage_section`', function()
    child.o.columns = 20
    edit('aaa')
    child.cmd('tabedit bbb')

    reload_module({ tabpage_section = 'left' })
    child.cmd('1tabnext')
    eq(
      eval_tabline(true),
      '%#MiniTablineTabpagesection# Tab 1/2 %#MiniTablineCurrent# aaa %#MiniTablineHidden# bbb %#MiniTablineFill#'
    )
    child.cmd('2tabnext')
    eq(
      eval_tabline(true),
      '%#MiniTablineTabpagesection# Tab 2/2 %#MiniTablineHidden# aaa %#MiniTablineCurrent# bbb %#MiniTablineFill#'
    )

    reload_module({ tabpage_section = 'right' })
    child.cmd('1tabnext')
    eq(
      eval_tabline(true),
      '%#MiniTablineCurrent# aaa %#MiniTablineHidden# bbb %#MiniTablineFill#%=%#MiniTablineTabpagesection# Tab 1/2 '
    )
    child.cmd('2tabnext')
    eq(
      eval_tabline(true),
      '%#MiniTablineHidden# aaa %#MiniTablineCurrent# bbb %#MiniTablineFill#%=%#MiniTablineTabpagesection# Tab 2/2 '
    )

    reload_module({ tabpage_section = 'none' })
    child.cmd('1tabnext')
    eq(eval_tabline(true), '%#MiniTablineCurrent# aaa %#MiniTablineHidden# bbb %#MiniTablineFill#')
    child.cmd('2tabnext')
    eq(eval_tabline(true), '%#MiniTablineHidden# aaa %#MiniTablineCurrent# bbb %#MiniTablineFill#')
  end)

  it('validates `config.tabpage_section`', function()
    child.o.cmdheight = 10
    child.lua([[MiniTabline.config.tabpage_section = 'aaa']])
    child.cmd('tabedit')
    eq(
      child.cmd_capture('1messages'),
      [[(mini.tabline) `config.tabpage_section` should be one of 'left', 'right', 'none'.]]
    )
  end)

  it('shows only listed buffers', function()
    child.cmd('edit aaa | edit bbb | set nobuflisted | help')
    eq(eval_tabline(), ' aaa ')
  end)

  it('works with "problematic" labels', function()
    -- Problematic characters: '.', '%'
    child.cmd([[edit tests/tabline-tests/dir1/bad\%new.file.lua]])

    -- Should have double `%` to escape it and show properly
    eq(eval_tabline(), ' bad%%new.file.lua ')
  end)

  it('attaches correct highlight group', function()
    child.cmd('edit aaa')
    local buf_aaa = child.api.nvim_get_current_buf()
    child.cmd('edit bbb')
    local buf_bbb = child.api.nvim_get_current_buf()
    child.cmd('vsplit | edit ccc')
    local buf_ccc = child.api.nvim_get_current_buf()

    -- Highlight groups for non-modified buffers
    eq(
      eval_tabline(true),
      '%#MiniTablineHidden# aaa %#MiniTablineVisible# bbb %#MiniTablineCurrent# ccc %#MiniTablineFill#'
    )

    child.api.nvim_buf_set_lines(buf_aaa, 0, -1, true, { 'AAA' })
    child.api.nvim_buf_set_lines(buf_bbb, 0, -1, true, { 'BBB' })
    child.api.nvim_buf_set_lines(buf_ccc, 0, -1, true, { 'CCC' })

    -- Highlight groups for modified buffers
    eq(
      eval_tabline(true),
      '%#MiniTablineModifiedHidden# aaa %#MiniTablineModifiedVisible# bbb %#MiniTablineModifiedCurrent# ccc %#MiniTablineFill#'
    )
  end)

  it('attaches correct highlight group to unnamed buffers', function()
    local buf_scratch = child.api.nvim_create_buf(true, true)
    child.api.nvim_buf_set_lines(0, 0, -1, true, { 'NONAME' })
    child.api.nvim_buf_set_lines(buf_scratch, 0, -1, true, { 'SCRATCH' })
    -- Scratch buffers can't be 'modified', so don't use `*Modified*` group
    eq(eval_tabline(true), '%#MiniTablineModifiedCurrent# * %#MiniTablineHidden# !(2) %#MiniTablineFill#')
  end)

  it('respects `config.show_icons`', function()
    mock_devicons()

    -- If `true`, should add icons if `nvim-web-devicons` is found
    child.cmd('edit LICENSE | edit aaa.lua')
    eq(eval_tabline(true), '%#MiniTablineHidden#  LICENSE %#MiniTablineCurrent#  aaa.lua %#MiniTablineFill#')

    -- If `false`, should not add icons
    reload_module({ show_icons = false })
    child.cmd('bnext')
    eq(eval_tabline(true), '%#MiniTablineCurrent# LICENSE %#MiniTablineHidden# aaa.lua %#MiniTablineFill#')
  end)

  it('deduplicates named labels', function()
    edit_path('dir1/aaa')
    eq(eval_tabline(), ' aaa ')

    edit_path('dir2/aaa')
    eq(eval_tabline(), ' dir1/aaa  dir2/aaa ')

    edit_path('dir1/dir_nested/aaa')
    eq(eval_tabline(), ' dir1/aaa  dir2/aaa  dir_nested/aaa ')

    -- Should deduplicate only to level where it makes a difference
    edit_path('dir2/dir_nested/aaa')
    eq(eval_tabline(), ' dir1/aaa  dir2/aaa  dir1/dir_nested/aaa  dir2/dir_nested/aaa ')

    -- Should work for buffers without initial path
    local buf_id = child.api.nvim_create_buf(true, false)
    child.api.nvim_buf_set_name(buf_id, 'aaa')
    local cur_dir_basename = child.fn.fnamemodify(child.fn.getcwd(), ':t')
    eq(
      eval_tabline(),
      (' dir1/aaa  dir2/aaa  dir1/dir_nested/aaa  dir2/dir_nested/aaa  %s/aaa '):format(cur_dir_basename)
    )
  end)

  it('deduplicates independent of current working directory', function()
    edit_path('dir1/aaa')
    edit_path('dir1/dir_nested/aaa')

    child.cmd('cd tests/tabline-tests/dir1')
    eq(eval_tabline(), ' dir1/aaa  dir_nested/aaa ')
  end)

  it('deduplicates unnamed labels', function()
    -- First unnamed buffer should not have id beside it
    eq(eval_tabline(), ' * ')

    -- Identifier should sequentially track all buffers
    local buf_id = child.api.nvim_create_buf(true, false)
    eq(eval_tabline(), ' *  *(2) ')

    -- Identifiers should continue even if previous one is deleted
    child.api.nvim_buf_delete(buf_id, { force = true })
    eq(eval_tabline(), ' * ')
    child.api.nvim_create_buf(true, false)
    eq(eval_tabline(), ' *  *(3) ')

    -- Should use single identifier stream for all types of unnamed labels
    child.api.nvim_create_buf(true, true)
    eq(eval_tabline(), ' *  *(3)  !(4) ')
    set_lines({ 'AAA' })
    child.cmd('cbuffer | copen')
    eq(eval_tabline(), ' *  *(3)  !(4)  *quickfix*(5) ')
  end)

  it('dedpulicates with "problematic" paths', function()
    -- Problematic characters: '.', '%'
    edit_path('dir1/aaa')
    edit_path([[bad\%new.dir/aaa]])
    -- Should have double `%` to escape it and show properly
    eq(eval_tabline(), ' dir1/aaa  bad%%new.dir/aaa ')
  end)

  it('fits to display width', function()
    child.o.columns = 15

    -- Display width is bigger than needed
    edit('aaa')
    edit('bbb')
    eq(eval_tabline(), ' aaa  bbb ')

    -- Display width is exactly as needed
    edit('ccc')
    eq(eval_tabline(), ' aaa  bbb  ccc ')

    -- Display width is smaller than needed
    edit('ddd')
    eq(eval_tabline(), ' bbb  ccc  ddd ')
  end)

  it('fits to display width in case of multiple tabs', function()
    child.o.columns = 20
    edit('aaaaaaaa')
    child.cmd('tabedit')
    edit('bbbbbbbb')

    reload_module({ tabpage_section = 'left' })
    child.cmd('1tabnext')
    eq(eval_tabline(), ' Tab 1/2 aaaaa  bbbb')
    child.cmd('2tabnext')
    eq(eval_tabline(), ' Tab 2/2   bbbbbbbb ')

    reload_module({ tabpage_section = 'right' })
    child.cmd('1tabnext')
    eq(eval_tabline(), 'aaaaa  bbbb%= Tab 1/2 ')
    child.cmd('2tabnext')
    eq(eval_tabline(), '  bbbbbbbb %= Tab 2/2 ')

    reload_module({ tabpage_section = 'none' })
    child.cmd('1tabnext')
    eq(eval_tabline(), ' aaaaaaaa  bbbbbbbb ')
    child.cmd('2tabnext')
    eq(eval_tabline(), ' aaaaaaaa  bbbbbbbb ')
  end)

  it('properly centers current buffer', function()
    local get_buf_name = function(buf_id)
      buf_id = buf_id or 0
      buf_id = buf_id == 0 and child.api.nvim_get_current_buf() or buf_id
      return child.fn.bufname(buf_id)
    end

    child.o.columns = 25
    vim.tbl_map(edit, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff', 'ggg' })

    -- Should not move "left" buffers to center
    edit('aaa')
    eq(get_buf_name(), 'aaa')
    eq(eval_tabline(), ' aaa  bbb  ccc  ddd  eee ')

    edit('bbb')
    eq(get_buf_name(), 'bbb')
    eq(eval_tabline(), ' aaa  bbb  ccc  ddd  eee ')

    -- Should center right end (which is ' ') of "middle" buffers
    edit('ccc')
    eq(eval_tabline(), 'aa  bbb  ccc  ddd  eee  f')
    edit('ddd')
    eq(eval_tabline(), 'bb  ccc  ddd  eee  fff  g')

    -- Should not move "right" buffers to center
    edit('eee')
    eq(eval_tabline(), ' ccc  ddd  eee  fff  ggg ')
    edit('fff')
    eq(eval_tabline(), ' ccc  ddd  eee  fff  ggg ')
    edit('ggg')
    eq(eval_tabline(), ' ccc  ddd  eee  fff  ggg ')

    -- Should pick center buffer only from those shown in tabline
    child.cmd('help')
    eq(eval_tabline(), ' ccc  ddd  eee  fff  ggg ')
  end)

  it('properly truncates left and right tabs', function()
    local validate = function(columns, strings)
      local cache_columns = child.o.columns
      child.o.columns = columns
      eq(eval_tabline(true), table.concat(strings))
      child.o.columns = cache_columns
    end

    for _, name in ipairs({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' }) do
      edit(name)
    end
    edit('ccc')

    -- Should preserve highlight group from truncated tabs (even whitespace)
    validate(22, {
      '%#MiniTablineHidden# ',
      '%#MiniTablineHidden# bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# eee ',
      '%#MiniTablineHidden# ',
      '%#MiniTablineFill#',
    })
    -- For odd display width "actual center" is between second to last and last
    -- characters of center label
    validate(21, {
      '%#MiniTablineHidden# ',
      '%#MiniTablineHidden# bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# eee ',
      '%#MiniTablineFill#',
    })
    validate(20, {
      '%#MiniTablineHidden# bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# eee ',
      '%#MiniTablineFill#',
    })
    validate(19, {
      '%#MiniTablineHidden# bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# eee',
      '%#MiniTablineFill#',
    })
    validate(18, {
      '%#MiniTablineHidden#bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# eee',
      '%#MiniTablineFill#',
    })
    validate(17, {
      '%#MiniTablineHidden#bbb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# ee',
      '%#MiniTablineFill#',
    })
    validate(16, {
      '%#MiniTablineHidden#bb %#MiniTablineCurrent# ccc ',
      '%#MiniTablineHidden# ddd %#MiniTablineHidden# ee',
      '%#MiniTablineFill#',
    })
  end)

  it('properly truncates in edge cases', function()
    -- Too wide center label
    edit('aaaaaaaaaa')
    edit('bbbbbbbbbb')
    child.o.columns = 15

    edit('aaaaaaaaaa')
    eq(eval_tabline(), 'aaaaaaa  bbbbbb')
  end)

  local validate_columns = function(columns, string)
    local cache_columns = child.o.columns
    child.o.columns = columns
    eq(eval_tabline(), string)
    child.o.columns = cache_columns
  end

  it('handles multibyte characters in labels', function()
    for _, name in ipairs({ 'ббб', 'ввв', 'ггг', 'ддд', 'жжж', 'ззз' }) do
      edit(name)
    end
    edit('ггг')

    validate_columns(20, ' ввв  ггг  ддд  жжж ')
    validate_columns(19, ' ввв  ггг  ддд  жжж')
    validate_columns(18, 'ввв  ггг  ддд  жжж')
    validate_columns(17, 'ввв  ггг  ддд  жж')
    validate_columns(16, 'вв  ггг  ддд  жж')
    validate_columns(15, 'вв  ггг  ддд  ж')
  end)

  it('handles multibyte icons', function()
    mock_devicons()

    edit('LICENSE')
    edit('aaaa.lua')
    edit('bbbb.txt')

    child.o.columns = 15
    eq(eval_tabline(), 'ua   bbbb.txt ')

    edit('aaaa.lua')
    eq(eval_tabline(), 'aaa.lua   bbbb')

    validate_columns(16, 'aaa.lua   bbbb.')
    validate_columns(17, 'aaaa.lua   bbbb.')
    validate_columns(18, 'aaaa.lua   bbbb.t')
    validate_columns(19, ' aaaa.lua   bbbb.t')
    validate_columns(20, ' aaaa.lua   bbbb.tx')
    validate_columns(21, ' aaaa.lua   bbbb.tx')
  end)

  it('respects vim.{g,b}.minitabline_disable', function()
    local validate_disable = function(var_type)
      child[var_type].minitabline_disable = true
      eq(eval_tabline(), '')

      child[var_type].minitabline_disable = nil
    end

    validate_disable('g')
    validate_disable('b')
  end)
end)

-- Functional tests ===========================================================
describe('Mouse click', function()
  before_each(function()
    child.setup()
    load_module()
  end)

  local click = function(column)
    child.api.nvim_input_mouse('left', 'press', '', 0, 0, column)
  end

  it('works', function()
    edit('aaa')
    edit('bbb')
    eq(child.fn.bufname(), 'bbb')
    eq(eval_tabline(true), '%#MiniTablineHidden# aaa %#MiniTablineCurrent# bbb %#MiniTablineFill#')

    -- Clicking within tab should result in buffer becoming current while
    -- updating highlight
    click(0)
    eq(child.fn.bufname(), 'aaa')
    eq(eval_tabline(true), '%#MiniTablineCurrent# aaa %#MiniTablineHidden# bbb %#MiniTablineFill#')

    -- More granular checks for tabline ' aaa  bbb '
    click(5)
    eq(child.fn.bufname(), 'bbb')
    click(4)
    eq(child.fn.bufname(), 'aaa')

    click(6)
    eq(child.fn.bufname(), 'bbb')
    click(3)
    eq(child.fn.bufname(), 'aaa')

    -- Clicking to the right of actual lable shouldn't do anything
    click(9)
    eq(child.fn.bufname(), 'bbb')
    edit('aaa')

    eq(child.fn.bufname(), 'aaa')
    click(10)
    eq(child.fn.bufname(), 'aaa')
  end)

  it('works in case of multiple tabs', function()
    edit('aaa')
    child.cmd('tabedit bbb')

    reload_module({ tabpage_section = 'left' })
    eq(child.fn.bufname(), 'bbb')
    eq(eval_tabline(), ' Tab 2/2  aaa  bbb ')

    -- Clicking on tabpage section shouldn't do anything
    click(0)
    eq(child.fn.bufname(), 'bbb')
    eq(eval_tabline(), ' Tab 2/2  aaa  bbb ')

    -- Clicking between right label and tabpage section shouldn't do anything
    child.o.columns = 40
    reload_module({ tabpage_section = 'right' })
    edit('aaa')
    eq(child.fn.bufname(), 'aaa')
    eq(eval_tabline(), ' aaa  bbb %= Tab 2/2 ')

    click(20)
    eq(child.fn.bufname(), 'aaa')
    eq(eval_tabline(), ' aaa  bbb %= Tab 2/2 ')
  end)
end)

child.stop()
