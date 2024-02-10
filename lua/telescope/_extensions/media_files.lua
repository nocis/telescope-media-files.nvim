local has_telescope, telescope = pcall(require, "telescope")

-- TODO: make dependency errors occur in a better way
if not has_telescope then
  error("This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)")
end


local utils = require('telescope.utils')
local defaulter = utils.make_default_callable
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')
local conf = require('telescope.config').values
local Path = require("plenary.path")
local from_entry = require("telescope.from_entry")

local M = {}

local filetypes = {}
local find_cmd = ""
local image_stretch = 250

M.base_directory=""
M.media_preview = defaulter(function(opts)
  local cwd = opts.cwd or vim.loop.cwd()
  return previewers.new_termopen_previewer {
    title = "File Preview",
    dyn_title = function(_, entry)
      return Path:new(from_entry.path(entry, false, false)):normalize(cwd)
    end,
    get_command = opts.get_command or function(entry, status)
      local filename = from_entry.path(entry, true, false)
      local get_file_stat = function(filename)
        return vim.loop.fs_stat(vim.fn.expand(filename)) or {}
      end
      local list_dir = (function()
          return function(dirname)
             return { "ls", "-la", vim.fn.expand(dirname) }
          end
      end)()
        
      local et = get_file_stat(filename).type
      print(et)
      local fset = {"png", "jpg", "gif", "mp4", "webm", "pdf"}
      if fset[et] == nil then
          if get_file_stat(filename).type == "directory" then
            return list_dir(filename)
          end

          if 1 == vim.fn.executable "file" then
            local output = utils.get_os_command_output { "file", "--mime-type", "-b", filename }
            local mime_type = vim.split(output[1], "/")[1]
            if mime_type ~= "text" then
              return { "echo", "Binary file found. These files cannot be displayed!" }
            end
          end
          
          return {
            "cat",
            "--",
            vim.fn.expand(filename),
          }
         
      else
        local sourced_file = require('plenary.debug_utils').sourced_filepath()
        local base_directory = vim.fn.fnamemodify(sourced_file, ":h:h:h:h")
        local tmp_table = vim.split(entry.value,"\t");
        local win_id = status.layout.preview and status.layout.preview.winid
        local height = vim.api.nvim_win_get_height(win_id)
        local width = vim.api.nvim_win_get_width(win_id)
        local lnum = entry.lnum or 0
        
        opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()
        if vim.tbl_isempty(tmp_table) then
          return {"echo", ""}
        end
        return {
          base_directory .. '/scripts/vimg' ,
          tmp_table[1],
          0 ,
          lnum,
          width ,
          height,
          image_stretch
        } 
      end
    end
  }
end, {})

function M.media_files(opts)
  local find_commands = {
    find = {
      'find',
      '.',
      '-iregex',
      [[.*\.\(]]..table.concat(filetypes,"\\|") .. [[\)$]]
    },
    fd = {
      'fd',
      '--type',
      'f',
      '--regex',
      [[.*.(]]..table.concat(filetypes,"|") .. [[)$]],
      '.'
    },
    fdfind = {
      'fdfind',
      '--type',
      'f',
      '--regex',
      [[.*.(]]..table.concat(filetypes,"|") .. [[)$]],
      '.'
    },
    rg = {
      'rg',
      '--files',
      '--glob',
      [[*.{]]..table.concat(filetypes,",") .. [[}]],
      '.'
    },
  }

  if not vim.fn.executable(find_cmd) then
    error("You don't have "..find_cmd.."! Install it first or use other finder.")
    return
  end

  if not find_commands[find_cmd] then
    error(find_cmd.." is not supported!")
    return
  end

  local sourced_file = require('plenary.debug_utils').sourced_filepath()
  M.base_directory = vim.fn.fnamemodify(sourced_file, ":h:h:h:h")
  opts = opts or {}
  opts.attach_mappings= function(prompt_bufnr,map)
    actions.select_default:replace(function()
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if entry[1] then
        local filename = entry[1]
        vim.fn.setreg(vim.v.register, filename)
        vim.notify("The image path has been copied!")
      end
    end)
    return true
  end
  opts.path_display = { "shorten" }

  local popup_opts={}
  opts.get_preview_window=function ()
    return popup_opts.preview
  end
  local picker=pickers.new(opts, {
    prompt_title = 'Media Files',
    finder = finders.new_oneshot_job(
      find_commands[find_cmd],
      opts
    ),
    previewer = M.media_preview.new(opts),
    sorter = conf.file_sorter(opts),
  })


  local line_count = vim.o.lines - vim.o.cmdheight
  if vim.o.laststatus ~= 0 then
    line_count = line_count - 1
  end
  popup_opts = picker:get_window_options(vim.o.columns, line_count)
  picker:find()
end


return require('telescope').register_extension {
  setup = function(ext_config)
    filetypes = ext_config.filetypes or {"png", "jpg", "gif", "mp4", "webm", "pdf"}
    find_cmd = ext_config.find_cmd or "fd"
    image_stretch = ext_config.image_stretch or 250
  end,
  exports = {
    media_files = M.media_files,
    media_preview = M.media_preview
  },
}
