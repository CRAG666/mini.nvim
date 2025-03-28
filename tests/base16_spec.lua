local helpers = require('tests.helpers')

local child = helpers.new_child_neovim()
local eq = assert.are.same

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('base16', config) end
local unload_module = function() child.mini_unload('base16') end
local reload_module = function(config) unload_module(); load_module(config) end
--stylua: ignore end

local validate_hl_group = function(group_name, target)
  eq(child.cmd_capture('highlight ' .. group_name):gsub(' +', ' '), group_name .. ' xxx ' .. target)
end

-- Data =======================================================================
local minischeme_palette = {
  base00 = '#112641',
  base01 = '#3a475e',
  base02 = '#606b81',
  base03 = '#8691a7',
  base04 = '#d5dc81',
  base05 = '#e2e98f',
  base06 = '#eff69c',
  base07 = '#fcffaa',
  base08 = '#ffcfa0',
  base09 = '#cc7e46',
  base0A = '#46a436',
  base0B = '#9ff895',
  base0C = '#ca6ecf',
  base0D = '#42f7ff',
  base0E = '#ffc4ff',
  base0F = '#00a5c5',
}

local minischeme_use_cterm = {
  base00 = 235,
  base01 = 238,
  base02 = 60,
  base03 = 103,
  base04 = 186,
  base05 = 186,
  base06 = 229,
  base07 = 229,
  base08 = 223,
  base09 = 173,
  base0A = 71,
  base0B = 156,
  base0C = 170,
  base0D = 87,
  base0E = 225,
  base0F = 38,
}

-- Unit tests =================================================================
describe('MiniBase16.setup()', function()
  before_each(function()
    child.setup()
    load_module({ palette = minischeme_palette })
  end)

  it('creates side effects', function()
    -- Global variable
    assert.True(child.lua_get('_G.MiniBase16 ~= nil'))
  end)

  it('creates `config` field', function()
    assert.True(child.lua_get([[type(_G.MiniBase16.config) == 'table']]))

    -- Check default values
    local assert_config = function(field, value)
      eq(child.lua_get('MiniBase16.config.' .. field), value)
    end

    assert_config('palette', minischeme_palette)
    assert_config('use_cterm', vim.NIL)
  end)

  it('respects `config` argument', function()
    unload_module()
    load_module({ palette = minischeme_palette, use_cterm = true })
    assert.True(child.lua_get([[MiniBase16.config.use_cterm == true]]))
  end)

  it('validates `config` argument', function()
    unload_module()

    local assert_config_error = function(config, name, target_type)
      assert.error_matches(function()
        load_module(config)
      end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
    end

    assert_config_error('a', 'config', 'table')
    assert_config_error({ palette = 'a' }, 'config.palette', 'table')
    assert_config_error({ palette = { 'a' } }, 'config.palette', 'base00')
    assert_config_error({ palette = { base00 = 1 } }, 'config.palette', 'HEX')
    assert_config_error({ palette = { base00 = '000' } }, 'config.palette.base00', 'HEX')
    assert_config_error({ palette = { base00 = '000000' } }, 'config.palette.base00', 'HEX')
    assert_config_error({ palette = { base00 = '#GGGGGG' } }, 'config.palette.base00', 'HEX')
    assert_config_error({ palette = minischeme_palette, use_cterm = 'a' }, 'use_cterm', 'boolean or table')
    assert_config_error({ palette = minischeme_palette, use_cterm = { 'a' } }, 'use_cterm', 'base00')
    assert_config_error(
      { palette = minischeme_palette, use_cterm = { base00 = 'a' } },
      'use_cterm.base00',
      'cterm color'
    )
    assert_config_error(
      { palette = minischeme_palette, use_cterm = { base00 = -1 } },
      'use_cterm.base00',
      'cterm color'
    )
  end)

  it('defines builtin highlight groups', function()
    local p = child.lua_get('MiniBase16.config.palette')
    validate_hl_group('Normal', ('guifg=%s guibg=%s'):format(p.base05, p.base00))
    validate_hl_group('Cursor', ('guifg=%s guibg=%s'):format(p.base00, p.base05))
    validate_hl_group('SpellBad', ('ctermbg=9 gui=%s guisp=%s'):format('undercurl', p.base08))

    -- Don't test exact values on Neovim<=0.5.1 due to CI difficulties
    if vim.fn.has('nvim-0.6.0') == 0 then
      return
    end

    validate_hl_group('Comment', ('ctermfg=14 guifg=%s'):format(p.base03))
    validate_hl_group('Error', ('ctermfg=15 ctermbg=9 guifg=%s guibg=%s'):format(p.base00, p.base08))
    validate_hl_group('Special', ('ctermfg=224 guifg=%s'):format(p.base0C))
    validate_hl_group('Bold', 'gui=bold')

    local diagnostic_hl_group = vim.fn.has('nvim-0.6.0') == 1 and 'DiagnosticError' or 'LspDiagnosticsDefaultWarning'
    validate_hl_group(diagnostic_hl_group, ('ctermfg=1 guifg=%s guibg=%s'):format(p.base08, p.base00))
  end)

  it('defines highlight groups for explicitly supported plugins', function()
    local p = child.lua_get('MiniBase16.config.palette')
    validate_hl_group('MiniTrailspace', ('guifg=%s guibg=%s'):format(p.base00, p.base08))
    validate_hl_group('NvimTreeRootFolder', ('guifg=%s'):format(p.base0E))
    validate_hl_group('GitSignsAdd', ('guifg=%s guibg=%s'):format(p.base0B, p.base01))
    validate_hl_group('TelescopeBorder', ('guifg=%s'):format(p.base0F))
    validate_hl_group('WhichKey', ('guifg=%s'):format(p.base0D))
  end)

  it('defines highlight groups for terminal colors', function()
    local p = child.lua_get('MiniBase16.config.palette')
    vim.g.terminal_color_0 = p.base00
    vim.g.terminal_color_background = vim.o.background == 'dark' and vim.g.terminal_color_0 or vim.g.terminal_color_7
    vim.g.terminal_color_foreground = vim.o.background == 'dark' and vim.g.terminal_color_5 or vim.g.terminal_color_2
  end)

  it('clears previous colorscheme', function()
    local p = child.lua_get('MiniBase16.config.palette')
    child.cmd('colorscheme blue')
    load_module({ palette = minischeme_palette })
    validate_hl_group('Normal', ('guifg=%s guibg=%s'):format(p.base05, p.base00))
  end)

  it('respects `config.use_cterm`', function()
    local p = child.lua_get('MiniBase16.config.palette')
    local p_cterm = minischeme_use_cterm

    reload_module({ palette = minischeme_palette, use_cterm = true })
    validate_hl_group(
      'Normal',
      ('ctermfg=%s ctermbg=%s guifg=%s guibg=%s'):format(p_cterm.base05, p_cterm.base00, p.base05, p.base00)
    )

    reload_module({ palette = minischeme_palette, use_cterm = p_cterm })
    validate_hl_group(
      'Normal',
      ('ctermfg=%s ctermbg=%s guifg=%s guibg=%s'):format(p_cterm.base05, p_cterm.base00, p.base05, p.base00)
    )
  end)
end)

describe('MiniBase16.mini_palette()', function()
  child.setup()
  load_module({ palette = minischeme_palette })

  it('validates arguments', function()
    local validate = function(args, error_pattern)
      assert.error_matches(function()
        child.lua_get([[MiniBase16.mini_palette(...)]], args)
      end, error_pattern)
    end

    validate({ 1, '#000000' }, 'background.*HEX')
    validate({ 'a', '#000000' }, 'background.*HEX')
    validate({ '000000', '#000000' }, 'background.*HEX')
    validate({ '#GGGGGG', '#000000' }, 'background.*HEX')

    validate({ '#000000', 1 }, 'foreground.*HEX')
    validate({ '#000000', 'a' }, 'foreground.*HEX')
    validate({ '#000000', '000000' }, 'foreground.*HEX')
    validate({ '#000000', '#GGGGGG' }, 'foreground.*HEX')

    validate({ '#000000', '#FFFFFF', 'a' }, 'accent_chroma.*number')
    validate({ '#000000', '#FFFFFF', -1 }, 'accent_chroma.*positive')
  end)

  it('works', function()
    eq(child.lua_get([[MiniBase16.mini_palette('#112641', '#e2e98f', 75)]]), minischeme_palette)
  end)
end)

describe('MiniBase16.rgb_palette_to_cterm_palette()', function()
  child.setup()
  load_module({ palette = minischeme_palette })

  it('validates arguments', function()
    local validate = function(palette, error_pattern)
      assert.error_matches(function()
        child.lua_get([[MiniBase16.rgb_palette_to_cterm_palette(...)]], { palette })
      end, error_pattern)
    end

    validate('a', 'palette.*table')
    validate({ 'a' }, 'palette.*base00')
    validate({ base00 = 1 }, 'palette.*HEX')
    validate({ base00 = '000' }, 'palette.base00.*HEX')
    validate({ base00 = '000000' }, 'palette.base00.*HEX')
    validate({ base00 = '#GGGGGG' }, 'palette.base00.*HEX')
  end)

  it('works', function()
    eq(child.lua_get('MiniBase16.rgb_palette_to_cterm_palette(...)', { minischeme_palette }), minischeme_use_cterm)
  end)
end)

describe('minischeme colorscheme', function()
  before_each(function()
    child.setup()
  end)

  it('works with dark background', function()
    child.cmd('set background=dark')
    child.cmd('colorscheme minischeme')
    validate_hl_group('Normal', 'ctermfg=186 ctermbg=235 guifg=#e2e98f guibg=#112641')
  end)

  it('works with light background', function()
    child.cmd('set background=light')
    child.cmd('colorscheme minischeme')
    validate_hl_group('Normal', 'ctermfg=18 ctermbg=254 guifg=#002a83 guibg=#e2e5ca')
  end)
end)

child.stop()
